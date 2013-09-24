require 'yell'

require 'traject'
require 'traject/qualified_const_get'

require 'traject/indexer/settings'
require 'traject/marc_reader'
require 'traject/marc4j_reader'
require 'traject/json_writer'
require 'traject/solrj_writer'

require 'traject/macros/marc21'
require 'traject/macros/basic'
#
#  == Readers and Writers
#
#  The Indexer has a modularized architecture for readers and writers, for where
#  source records come from (reader), and where output is sent to (writer).
#
#  A Reader is any class that:
#   1) Has a two-argument initializer taking an IO stream and a Settings hash
#   2) Responds to the usual ruby #each, returning a source record from each #each.
#      (Including Enumerable is prob a good idea too)
#
#  The default reader is the Traject::MarcReader, who's behavior is
#  further customized by several settings in the Settings hash.
#
#  Alternate readers can be set directly with the #reader_class= method, or
#  with the "reader_class_name" Setting, a String name of a class
#  meeting the reader contract.
#
#
#  A Writer is any class that:
#  1) Has a one-argument initializer taking a Settings hash. (The logger
#     is provided to the Writer in settings["logger"])
#  2) Responds to a one argument #put method, where the argument is
#     a Traject::Indexer::Context, containing an #output_hash
#     hash of mapped keys/values. The writer should write them
#     to the appropriate place.
#  3) Responds to a #close method, called when we're done.
#  4) Optionally implements a #skipped_record_count method, returning int count of records
#     that were skipped due to errors (and presumably logged)
#
#  The default writer (will be) the SolrWriter , which is configured
#  through additional Settings as well. A JsonWriter is also available,
#  which can be useful for debugging your index mappings.
#
#  You can set alternate writers by setting a Class object directly
#  with the #writer_class method, or by the 'writer_class_name' Setting,
#  with a String name of class meeting the Writer contract.
#
class Traject::Indexer

  # Arity error on a passed block
  class ArityError < ArgumentError; end
  class NamingError < ArgumentError; end



  include Traject::QualifiedConstGet

  attr_writer :reader_class, :writer_class

  # For now we hard-code these basic macro's included
  # TODO, make these added with extend per-indexer,
  # added by default but easily turned off (or have other
  # default macro modules provided)
  include Traject::Macros::Marc21
  include Traject::Macros::Basic


  # optional hash or Traject::Indexer::Settings object of settings.
  def initialize(arg_settings = {})
    @settings = Settings.new(arg_settings)
    @index_steps = []
  end

  # The Indexer's settings are a hash of key/values -- not
  # nested, just one level -- of configuration settings. Keys
  # are strings.
  #
  # The settings method with no arguments returns that hash.
  #
  # With a hash and/or block argument, can be used to set
  # new key/values. Each call merges onto the existing settings
  # hash.
  #
  #    indexer.settings("a" => "a", "b" => "b")
  #
  #    indexer.settings do
  #      store "b", "new b"
  #    end
  #
  #    indexer.settings #=> {"a" => "a", "b" => "new b"}
  #
  # even with arguments, returns settings hash too, so can
  # be chained.
  def settings(new_settings = nil, &block)
    @settings.merge!(new_settings) if new_settings

    @settings.instance_eval &block if block

    return @settings
  end

  def logger
    @logger ||= create_logger
  end
  attr_writer :logger


  # Just calculates the arg that's gonna be given to Yell.new
  # or SomeLogger.new
  def logger_argument
    specified = settings["log.file"] || "STDERR"

    case specified
    when "STDOUT" then STDOUT
    when "STDERR" then STDERR
    else specified
    end
  end

  # Second arg to Yell.new, options hash, calculated from
  # settings
  def logger_options
    # formatter, default is fairly basic
    format = settings["log.format"] || "%d %5L %m"
    format = case format
    when "false" then false
    when "" then nil
    else format
    end

    level = settings["log.level"] || "info"

    {:format => format, :level => level}
  end

  # Create logger according to settings
  def create_logger
    # log everything to STDERR or specified logfile
    logger = Yell.new( logger_argument, logger_options )
    # ADDITIONALLY log error and higher to....
    if settings["log.error_file"]
      logger.adapter :file, settings["log.error_file"], :level => 'gte.error'
    end

    return logger
  end





  # Used to define an indexing mapping.
  def to_field(field_name, aLambda = nil, &block)
    @index_steps << ToFieldStep.new(field_name, aLambda, block, Traject::Util.extract_caller_location(caller.first) )
  end

  def each_record(aLambda = nil, &block)
    @index_steps << EachRecordStep.new(aLambda, block, Traject::Util.extract_caller_location(caller.first) )
  end


  # Processes a single record according to indexing rules set up in
  # this indexer. Returns the output hash (a hash whose keys are
  # string fields, and values are arrays of one or more values in that field)
  #
  # This is a convenience shortcut for #map_to_context! -- use that one
  # if you want to provide addtional context
  # like position, and/or get back the full context.
  def map_record(record)
    context = Context.new(:source_record => record, :settings => settings)
    map_to_context!(context)
    return context.output_hash
  end

  # Maps a single record INTO the second argument, a Traject::Indexer::Context.
  #
  # Context must be passed with a #source_record and #settings, and optionally
  # a #position.
  #
  # Context will be mutated by this method, most significantly by adding
  # an #output_hash, a hash from fieldname to array of values in that field.
  #
  # Pass in a context with a set #position if you want that to be available
  # to mapping routines.
  #
  # Returns the context passed in as second arg, as a convenience for chaining etc.

  def map_to_context!(context)
    @index_steps.each do |index_step|
      # Don't bother if we're skipping this record
      break if context.skip?

      context.index_step = index_step
      accumulator = log_mapping_errors(context, index_step) do
        index_step.execute(context) # will always return [] for an each_record step
      end
      context.index_step =

      accumulator.compact!
      if accumulator.size > 0
        (context.output_hash[index_step.field_name] ||= []).concat accumulator
      end

      context.index_step = index_step
    end

    return context
  end

  # just a wrapper that captures and records any unexpected
  # errors raised in mapping, along with contextual information
  # on record and location in source file of mapping rule.
  #
  # Re-raises error at the moment.
  #
  # log_mapping_errors(context, index_step) do
  #    all_sorts_of_stuff # that will have errors logged
  # end
  def log_mapping_errors(context, index_step)
    begin
      yield
    rescue Exception => e
      msg =  "Unexpected error on record id `#{id_string(context.source_record)}` at file position #{context.position}\n"
      msg += "    while executing #{index_step.inspect}\n"
      msg += Traject::Util.exception_to_log_message(e)

      logger.error msg
      begin
        logger.debug "Record: " + context.source_record.to_s
      rescue Exception => marc_to_s_exception
        logger.debug "(Could not log record, #{marc_to_s_exception})"
      end

      raise e
    end
  end

  # get a printable id from record for error logging.
  # Maybe override this for a future XML version.
  def id_string(record)
    record && record['001'] && record['001'].value.to_s
  end

  # Processes a stream of records, reading from the configured Reader,
  # mapping according to configured mapping rules, and then writing
  # to configured Writer.
  #
  # returns 'false' as a signal to command line to return non-zero exit code
  # for some reason (reason found in logs, presumably). This particular mechanism
  # is open to complexification, starting simple. We do need SOME way to return
  # non-zero to command line.
  #
  def process(io_stream)
    settings.fill_in_defaults!

    count      =       0
    start_time = batch_start_time = Time.now
    logger.debug "beginning Indexer#process with settings: #{settings.inspect}"

    reader = self.reader!(io_stream)
    writer = self.writer!

    thread_pool = Traject::ThreadPool.new(settings["processing_thread_pool"].to_i)

    logger.info "   Indexer with reader: #{reader.class.name} and writer: #{writer.class.name}"

    log_batch_size = settings["log.batch_size"] && settings["log.batch_size"].to_i

    reader.each do |record; position|
      count += 1

      # have to use a block local var, so the changing `count` one
      # doesn't get caught in the closure. Weird, yeah.
      position = count

      thread_pool.raise_collected_exception!

      if settings["debug_ascii_progress"].to_s == "true"
        $stderr.write "." if count % settings["solrj_writer.batch_size"] == 0
      end

      if log_batch_size && (count % log_batch_size == 0)
        batch_rps = log_batch_size / (Time.now - batch_start_time)
        overall_rps = count / (Time.now - start_time)
        logger.info "Traject::Indexer#process, read #{count} records at id:#{id_string(record)}; #{'%.0f' % batch_rps}/s this batch, #{'%.0f' % overall_rps}/s overall"
        batch_start_time = Time.now
      end

      # we have to use this weird lambda to properly "capture" the count, instead
      # of having it be bound to the original variable in a non-threadsafe way.
      # This is confusing, I might not be understanding things properly, but that's where i am.
      #thread_pool.maybe_in_thread_pool &make_lambda(count, record, writer)
      thread_pool.maybe_in_thread_pool do
        context = Context.new(:source_record => record, :settings => settings, :position => position)
        context.logger = logger
        map_to_context!(context)
        if context.skip?
          log_skip(context)
        else
          writer.put context
        end

      end

    end
    $stderr.write "\n" if settings["debug_ascii_progress"].to_s == "true"

    logger.debug "Shutting down #processing mapper threadpool..."
    thread_pool.shutdown_and_wait
    logger.debug "#processing mapper threadpool shutdown complete."

    thread_pool.raise_collected_exception!


    writer.close if writer.respond_to?(:close)

    elapsed        = Time.now - start_time
    avg_rps        = (count / elapsed)
    logger.info "finished Indexer#process: #{count} records in #{'%.3f' % elapsed} seconds; #{'%.1f' % avg_rps} records/second overall."

    if writer.respond_to?(:skipped_record_count) && writer.skipped_record_count > 0
      logger.error "Indexer#process returning 'false' due to #{writer.skipped_record_count} skipped records."
      return false
    end

    return true
  end

  # Log that the current record is being skipped, using
  # data in context.position and context.skipmessage
  def log_skip(context)
    logger.debug "Skipped record #{context.position}: #{context.skipmessage}"
  end

  def reader_class
    unless defined? @reader_class
      @reader_class = qualified_const_get(settings["reader_class_name"])
    end
    return @reader_class
  end

  def writer_class
    unless defined? @writer_class
      @writer_class = qualified_const_get(settings["writer_class_name"])
    end
    return @writer_class
  end

  # Instantiate a Traject Reader, using class set
  # in #reader_class, initialized with io_stream passed in
  def reader!(io_stream)
    return reader_class.new(io_stream, settings.merge("logger" => logger))
  end

  # Instantiate a Traject Writer, suing class set in #writer_class
  def writer!
    return writer_class.new(settings.merge("logger" => logger))
  end

  # Represents the context of a specific record being indexed, passed
  # to indexing logic blocks
  #
  class Context
    def initialize(hash_init = {})
      # TODO, argument checking for required args?

      self.clipboard   = {}
      self.output_hash = {}

      hash_init.each_pair do |key, value|
        self.send("#{key}=", value)
      end

      @skip = false
    end

    attr_accessor :clipboard, :output_hash, :logger
    attr_accessor :index_step, :source_record, :settings
    # 1-based position in stream of processed records.
    attr_accessor :position

    # Should we be skipping this record?
    attr_accessor :skipmessage

    # Set the fact that this record should be skipped, with an
    # optional message
    def skip!(msg = '(no message given)')
      @skipmessage = msg
      @skip = true
    end

    # Should we skip this record?
    def skip?
      @skip
    end

  end



  # An indexing step definition, including it's source location
  # for logging
  #
  # This one represents an "each_record" step, a subclass below
  # for "to_field"
  #
  # source_location is just a string with filename and line number for
  # showing to devs in debugging.
  class EachRecordStep
    attr_accessor :source_location, :lambda, :block

    def initialize(lambda, block, source_location)
      self.lambda = lambda
      self.block = block
      self.source_location = source_location

      self.validate!
    end

    # raises if bad data
    def validate!
      unless self.lambda or self.block
        raise ArgumentError.new("Missing Argument: each_record must take a block/lambda as an argument (#{self.inspect})")
      end

      [self.lambda, self.block].each do |proc|
        # allow negative arity, meaning variable/optional, trust em on that.
        # but for positive arrity, we need 1 or 2 args
        if proc
          unless proc.is_a?(Proc)
            raise NamingError.new("argument to each_record must be a block/lambda, not a #{proc.class} #{self.inspect}")
          end
          if (proc.arity == 0 || proc.arity > 2)
            raise ArityError.new("block/proc given to each_record needs 1 or 2 arguments: #{self.inspect}")
          end
        end
      end
    end

    # For each_record, always return an empty array as the
    # accumulator, since it doesn't have those kinds of side effects
    def execute(context)
      [@lambda, @block].each do |aProc|
        next unless aProc

        if aProc.arity == 1
          aProc.call(context.source_record)
        else
          aProc.call(context.source_record, context)
        end

      end
      return [] # empty -- no accumulator for each_record
    end

    # Over-ride inspect for outputting error messages etc.
    def inspect
      "(each_record at #{source_location})"
    end
  end


  # An indexing step definition for a "to_field" step to specific
  # field.
  class ToFieldStep
    attr_accessor :field_name, :lambda, :block, :source_location
    def initialize(fieldname, lambda, block, source_location)
      self.field_name = fieldname
      self.lambda = lambda
      self.block = block
      self.source_location = source_location

      validate!
    end

    def validate!

      if self.field_name.nil? || !self.field_name.is_a?(String) || self.field_name.empty?
        raise NamingError.new("to_field requires the field name (as a string) as the first argument at #{self.source_location})")
      end

      [self.lambda, self.block].each do |proc|
        # allow negative arity, meaning variable/optional, trust em on that.
        # but for positive arrity, we need 2 or 3 args
        if proc && (proc.arity == 0 || proc.arity == 1 || proc.arity > 3)
          raise ArityError.new("error parsing field '#{self.field_name}': block/proc given to to_field needs 2 or 3 (or variable) arguments: #{proc} (#{self.inspect})")
        end
      end
    end

    # Override inspect for developer debug messages
    def inspect
      "(to_field #{self.field_name} at #{self.source_location})"
    end

    def execute(context)
      accumulator = []
      [@lambda, @block].each do |aProc|
        next unless aProc

        if aProc.arity == 2
          aProc.call(context.source_record, accumulator)
        else
          aProc.call(context.source_record, accumulator, context)
        end

      end
      return accumulator
    end

  end




end
