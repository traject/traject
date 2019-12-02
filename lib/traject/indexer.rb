require 'yell'

require 'traject/qualified_const_get'
require 'traject/thread_pool'

require 'traject/indexer/settings'
require 'traject/indexer/context'
require 'traject/indexer/step'

require 'traject/marc_reader'
require 'traject/json_writer'
require 'traject/solr_json_writer'
require 'traject/debug_writer'
require 'traject/array_writer'

require 'traject/macros/marc21'
require 'traject/macros/basic'
require 'traject/macros/transformation'

require 'traject/indexer/marc_indexer'


# This class does indexing for traject: Getting input records from a Reader
# class, mapping the input records to an output hash, and then sending the output
# hash off somewhere (usually Solr) with a Writer class.
#
# Traject config files are `instance_eval`d in an Indexer object, so `self` in
# a config file is an Indexer, and any Indexer methods can be called.
#
# However, certain Indexer methods exist mainly for the purpose of
# being called in config files; these methods are part of the expected
# Domain-Specific Language ("DSL") for config files, and will ordinarily
# form the bulk or entirety of config files:
#
# * #settings
# * #to_field
# * #each_record
# * #after_procesing
# * #logger (rarely used in config files, but in some cases to set up custom logging config)
#
#  ## Readers and Writers
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
#  further customized by several settings in the Settings hash. Jruby users
#  with specialized needs may want to look at the gem traject-marc4j_reader.
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
#  Traject packages one solr writer: traject/solr_json_writer, which sends
#  in json format and works under both ruby and  jruby, but only with solr version
#  >= 3.2. To index to an older solr installation, you'll need to use jruby and
#  install the gem traject-solrj_writer, which uses the solrj .jar underneath.
#
#  You can set alternate writers by setting a Class object directly
#  with the #writer_class method, or by the 'writer_class_name' Setting,
#  with a String name of class meeting the Writer contract. There are several
#  that ship with traject itself:
#
#  * traject/json_writer (Traject::JsonWriter) -- write newline-delimied json files.
#  * traject/yaml_writer (Traject::YamlWriter) -- write pretty yaml file; very human-readable
#  * traject/debug_writer (Traject::DebugWriter) -- write a tab-delimited file where
#    each line consists of the id, field, and value(s).
#  * traject/delimited_writer and traject/csv_writer -- write character-delimited files
#    (default is tab-delimited) or comma-separated-value files.
#
# ## Creating and Using an Indexer programmatically
#
# Normally the Traject::Indexer is created and used by a Traject::Command object.
# However, you can also create and use a Traject::Indexer programmatically, for embeddeding
# in your own ruby software. (Note, you will get best performance under Jruby only)
#
#      indexer = Traject::Indexer.new
#
# You can load a config file from disk, using standard ruby `instance_eval`.
# One benefit of loading one or more ordinary traject config files saved separately
# on disk is that these config files could also be used with the standard
# traject command line.
#
#      indexer.load_config_file(path_to_config)
#
# This may raise if the file is not readable. Or if the config file
# can't be evaluated, it will raise a Traject::Indexer::ConfigLoadError
# with a bunch of contextual information useful to reporting to developer.
#
# You can also instead, or in addition, write configuration inline using
# standard ruby `instance_eval`:
#
#     indexer.instance_eval do
#        to_field "something", literal("something")
#        # etc
#     end
#
# Or even load configuration from an existing lambda/proc object:
#
#     config = proc do
#       to_field "something", literal("something")
#     end
#     indexer.instance_eval &config
#
# It is least confusing to provide settings after you load
# config files, so you can determine if your settings should
# be defaults (taking effect only if not provided in earlier config),
# or should force themselves, potentially overwriting earlier config:
#
#      indexer.settings do
#         # default, won't overwrite if already set by earlier config
#         provide "solr.url", "http://example.org/solr"
#         provide "reader", "Traject::MarcReader"
#
#         # or force over any previous config
#         store "solr.url", "http://example.org/solr"
#      end
#
# Once your indexer is set up, you could use it to transform individual
# input records to output hashes. This method will ignore any readers
# and writers, and won't use thread pools, it just maps. Under
# standard MARC setup, `record` should be a `MARC::Record`:
#
#      output_hash = indexer.map_record(record)
#
# Or you could process an entire stream of input records from the
# configured reader, to the configured writer, as the traject command line
# does:
#
#      indexer.process(io_stream)
#      # or, eg:
#      File.open("path/to/input") do |file|
#        indexer.process(file)
#      end
#
# At present, you can only call #process _once_ on an indexer,
# but let us know if that's a problem, we could enhance.
#
# Please do let us know if there is some part of this API that is
# inconveient for you, we'd like to know your use case and improve things.
#
class Traject::Indexer
  CompletedStateError = Class.new(StandardError)
  ArityError          = Class.new(ArgumentError)
  NamingError         = Class.new(ArgumentError)

  include Traject::QualifiedConstGet
  extend Traject::QualifiedConstGet

  attr_writer :reader_class, :writer_class, :writer

  include Traject::Macros::Basic
  include Traject::Macros::Transformation


  # optional hash or Traject::Indexer::Settings object of settings.
  # optionally takes a block which is instance_eval'd in the indexer,
  # intended for configuration simimlar to what would be in a config file.
  def initialize(arg_settings = {}, &block)
    @writer_class           = nil
    @completed              = false
    @settings               = Settings.new(arg_settings).with_defaults(self.class.default_settings)
    @index_steps            = []
    @after_processing_steps = []

    self.class.apply_class_configure_block(self)
    instance_eval(&block) if block
  end

  # Right now just does an `instance_eval`, but encouraged in case we change the underlying
  # implementation later, and to make intent more clear.
  def configure(&block)
    instance_eval(&block)
  end

  ## Class level configure block(s) accepted too, and applied at instantiation
  #  before instance-level configuration.
  #
  #  EXPERIMENTAL, implementation may change in ways that effect some uses.
  #  https://github.com/traject/traject/pull/213
  #
  #  Note that settings set by 'provide' in subclass can not really be overridden
  #  by 'provide' in a next level subclass. Use self.default_settings instead, with
  #  call to super.
  #
  #  You can call this .configure multiple times, blocks are added to a list, and
  #  will be used to initialize an instance in order.
  #
  #  The main downside of this workaround implementation is performance, even though
  #  defined at load-time on class level, blocks are all executed on every instantiation.
  def self.configure(&block)
    (@class_configure_blocks ||= []) << block
  end

  def self.apply_class_configure_block(instance)
    # Make sure we inherit from superclass that has a class-level ivar @class_configure_block
    if self.superclass.respond_to?(:apply_class_configure_block)
      self.superclass.apply_class_configure_block(instance)
    end
    if @class_configure_blocks && !@class_configure_blocks.empty?
      @class_configure_blocks.each do |block|
        instance.configure(&block)
      end
    end
  end



  # Pass a string file path, a Pathname, or a File object, for
  # a config file to load into indexer.
  #
  # Can raise:
  # * Errno::ENOENT or Errno::EACCES if file path is not accessible
  # * Traject::Indexer::ConfigLoadError if exception is raised evaluating
  #   the config. A ConfigLoadError has information in it about original
  #   exception, and exactly what config file and line number triggered it.
  def load_config_file(file_path)
    File.open(file_path) do |file|
      begin
        self.instance_eval(file.read, file_path.to_s)
      rescue ScriptError, StandardError => e
        raise ConfigLoadError.new(file_path.to_s, e)
      end
    end
  end

  # Part of the config file DSL, for writing settings values.
  #
  # The Indexer's settings consist of a hash-like Traject::Settings
  # object. The settings hash is *not*  nested hashes, just one level
  # of configuration settings. Keys are always strings, and by convention
  # use "." for namespacing, eg `log.file`
  #
  # The settings method with no arguments returns that Settings object.
  #
  # With a hash and/or block argument, can be used to set
  # new key/values. Each call merges onto the existing settings
  # hash.  The block is `instance_eval`d in the context
  # of the Traject::Settings object.
  #
  #    indexer.settings("a" => "a", "b" => "b")
  #
  #    indexer.settings do
  #      provide "b", "new b"
  #    end
  #
  #    indexer.settings #=> {"a" => "a", "b" => "new b"}
  #
  # Note the #provide method is defined on Traject::Settings to
  # write to a setting only if previously not set. You can also
  # use #store to force over-writing even if an existing setting.
  #
  # Even with arguments, Indexer#settings returns the Settings object,
  # hash too, so can method calls can be chained.
  #
  def settings(new_settings = nil, &block)
    @settings.merge!(new_settings) if new_settings

    @settings.instance_eval(&block) if block_given?

    return @settings
  end

  # Hash is frozen to avoid inheritance-mutability confusion.
  def self.default_settings
    @default_settings ||= {
        # Writer defaults
        "writer_class_name"       => "Traject::SolrJsonWriter",
        "solr_writer.batch_size"  => 100,
        "solr_writer.thread_pool" => 1,

        # Threading and logging
        "processing_thread_pool"  => Traject::Indexer::Settings.default_processing_thread_pool,
        "log.batch_size.severity" => "info",

        # how to post-process the accumulator
        Traject::Indexer::ToFieldStep::ALLOW_NIL_VALUES => false,
        Traject::Indexer::ToFieldStep::ALLOW_DUPLICATE_VALUES  => true,
        Traject::Indexer::ToFieldStep::ALLOW_EMPTY_FIELDS => false
    }.freeze
  end


  # Not sure if allowing changing of default_settings is a good idea, but we do
  # use it in test. For now we make it private to require extreme measures to do it,
  # and advertise that this API could go away or change without a major version release,
  # it is experimental and internal.
  private_class_method def self.default_settings=(settings)
    @default_settings = settings
  end

  # Sub-classes should override to return a _proc_ object that takes one arg,
  # a source record, and returns an identifier for it that can be used in
  # logged messages. This differs depending on input record format, is why we
  # leave it to sub-classes.
  def source_record_id_proc
    if defined?(@@legacy_marc_mode) && @@legacy_marc_mode
      return @source_record_id_proc ||= lambda do |source_marc_record|
        if ( source_marc_record &&
             source_marc_record.kind_of?(MARC::Record) &&
             source_marc_record['001'] )
          source_marc_record['001'].value
        end
      end
    end

    @source_record_id_proc ||= lambda { |source| nil }
  end

  def self.legacy_marc_mode!
    @@legacy_marc_mode = true
    # include legacy Marc macros
    include Traject::Macros::Marc21

    # Reader defaults
    legacy_settings = {
      "reader_class_name"       => "Traject::MarcReader",
      "marc_source.type"        => "binary",
    }

    default_settings.merge!(legacy_settings)

    self
  end

  # Part of DSL, used to define an indexing mapping. Register logic
  # to be called for each record, and generate values for a particular
  # output field. The first field_name argument can be a single string, or
  # an array of multiple strings -- in the latter case, the processed values
  # will be added to each field mentioned.
  def to_field(field_name, *procs, &block)
    @index_steps << ToFieldStep.new(field_name, procs, block, Traject::Util.extract_caller_location(caller.first))
  end

  # Part of DSL, register logic to be called for each record
  def each_record(aLambda = nil, &block)
    @index_steps << EachRecordStep.new(aLambda, block, Traject::Util.extract_caller_location(caller.first))
  end

  # Part of DSL, register logic to be called once at the end
  # of processing a stream of records.
  def after_processing(aLambda = nil, &block)
    @after_processing_steps << AfterProcessingStep.new(aLambda, block, Traject::Util.extract_caller_location(caller.first))
  end

  def logger
    @logger ||= create_logger
  end

  attr_writer :logger


  def logger_format
    format = settings["log.format"] || "%d %5L %m"
    format = case format
               when "false" then
                 false
               when "" then
                 nil
               else
                 format
             end
  end

  # Create logger according to settings
  def create_logger
    if settings["logger"]
      # none of the other settings matter, we just got a logger
      return settings["logger"]
    end

    logger_level  = settings["log.level"] || "info"

    # log everything to STDERR or specified logfile
    logger        = Yell::Logger.new(:null)
    logger.format = logger_format
    logger.level  = logger_level

    logger_destination = settings["log.file"] || "STDERR"
    # We intentionally repeat the logger_level
    # on the adapter, so it will stay there if overall level
    # is changed.
    case logger_destination
      when "STDERR"
        logger.adapter :stderr, level: logger_level, format: logger_format
      when "STDOUT"
        logger.adapter :stdout, level: logger_level, format: logger_format
      else
        logger.adapter :file, logger_destination, level: logger_level, format: logger_format
    end


    # ADDITIONALLY log error and higher to....
    if settings["log.error_file"]
      logger.adapter :file, settings["log.error_file"], :level => 'gte.error'
    end

    return logger
  end


  # Processes a single record according to indexing rules set up in
  # this indexer. Returns the output hash (a hash whose keys are
  # string fields, and values are arrays of one or more values in that field)
  #
  # If the record is marked `skip` as part of processing, this will return
  # nil.
  #
  # This is a convenience shortcut for #map_to_context! -- use that one
  # if you want to provide addtional context
  # like position, and/or get back the full context.
  def map_record(record)
    context = Context.new(:source_record => record, :settings => settings, :source_record_id_proc => source_record_id_proc, :logger => logger)
    map_to_context!(context)
    return context.output_hash unless context.skip?
  end

  # Takes a single record, maps it, and sends it to the instance-configured
  # writer. No threading, no logging, no error handling. Respects skipped
  # records by not adding them. Returns the Traject::Indexer::Context.
  #
  # Aliased as #<<
  def process_record(record)
    check_uncompleted

    context = Context.new(:source_record => record, :settings => settings, :source_record_id_proc =>  source_record_id_proc, :logger => logger)
    map_to_context!(context)
    writer.put( context ) unless context.skip?

    return context
  end
  alias_method :<<, :process_record

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

      # Set the index step for error reporting
      context.index_step = index_step
      handle_mapping_errors(context) do
        index_step.execute(context) # will always return [] for an each_record step
      end

      # And unset the index step now that we're finished
      context.index_step = nil
    end

    return context
  end


  protected def default_mapping_rescue
    @default_mapping_rescue ||= lambda do |context, exception|
      msg = "Unexpected error on record #{context.record_inspect}\n"
      msg += "    while executing #{context.index_step.inspect}\n"

      msg += begin
        "\n    Record: #{context.source_record.to_s}\n"
      rescue StandardError => to_s_exception
        "\n    (Could not log record, #{to_s_exception})\n"
      end

      msg += Traject::Util.exception_to_log_message(exception)

      context.logger.error(msg) if context.logger

      raise exception
    end
  end

  # just a wrapper that catches any errors, and handles them. By default, logs
  # and re-raises. But you can set custom setting `mapping_rescue`
  # to customize
  #
  #
  # handle_mapping_errors(context, index_step) do
  #    all_sorts_of_stuff # that will have errors logged
  # end
  protected def handle_mapping_errors(context)
    begin
      yield
    rescue StandardError => e
      error_handler = settings["mapping_rescue"] || default_mapping_rescue
      error_handler.call(context, e)
    end
  end

  # Processes a stream of records, reading from the configured Reader,
  # mapping according to configured mapping rules, and then writing
  # to configured Writer.
  #
  # You instead give it an _array_ of streams, as well.
  #
  # returns 'false' as a signal to command line to return non-zero exit code
  # for some reason (reason found in logs, presumably). This particular mechanism
  # is open to complexification, starting simple. We do need SOME way to return
  # non-zero to command line.
  #
  # @param [#read, Array<#read>]
  def process(io_stream_or_array)
    check_uncompleted

    settings.fill_in_defaults!

    count      = 0
    start_time = batch_start_time = Time.now
    logger.debug "beginning Traject::Indexer#process with settings: #{settings.inspect}"

    processing_threads = settings["processing_thread_pool"].to_i
    thread_pool        = Traject::ThreadPool.new(processing_threads)

    logger.info "   Traject::Indexer with #{processing_threads} processing threads, reader: #{reader_class.name} and writer: #{writer.class.name}"

    #io_stream can now be an array of io_streams.
    (io_stream_or_array.kind_of?(Array) ? io_stream_or_array : [io_stream_or_array]).each do |io_stream|
      reader = self.reader!(io_stream)
      input_name = Traject::Util.io_name(io_stream)
      position_in_input = 0

      log_batch_size = settings["log.batch_size"] && settings["log.batch_size"].to_i

      reader.each do |record; safe_count, safe_position_in_input |
        count    += 1
        position_in_input += 1

        # have to use a block local var, so the changing `count` one
        # doesn't get caught in the closure. Don't totally get it, but
        # I think it's so.
        safe_count, safe_position_in_input = count, position_in_input

        thread_pool.raise_collected_exception!

        if settings["debug_ascii_progress"].to_s == "true"
          $stderr.write "." if count % settings["solr_writer.batch_size"].to_i == 0
        end

        context = Context.new(
            :source_record => record,
            :source_record_id_proc => source_record_id_proc,
            :settings      => settings,
            :position      => safe_count,
            :input_name    => input_name,
            :position_in_input => safe_position_in_input,
            :logger        => logger
        )


        if log_batch_size && (count % log_batch_size == 0)
          batch_rps   = log_batch_size / (Time.now - batch_start_time)
          overall_rps = count / (Time.now - start_time)
          logger.send(settings["log.batch_size.severity"].downcase.to_sym, "Traject::Indexer#process, read #{count} records at: #{context.record_inspect}; #{'%.0f' % batch_rps}/s this batch, #{'%.0f' % overall_rps}/s overall")
          batch_start_time = Time.now
        end

        # We pass context in a block arg to properly 'capture' it, so
        # we don't accidentally share the local var under closure between
        # threads.
        thread_pool.maybe_in_thread_pool(context) do |t_context|
          map_to_context!(t_context)
          if context.skip?
            log_skip(t_context)
          else
            writer.put t_context
          end
        end
      end
    end
    $stderr.write "\n" if settings["debug_ascii_progress"].to_s == "true"

    logger.debug "Shutting down #processing mapper threadpool..."
    thread_pool.shutdown_and_wait
    logger.debug "#processing mapper threadpool shutdown complete."

    thread_pool.raise_collected_exception!

    complete

    elapsed = Time.now - start_time
    avg_rps = (count / elapsed)
    logger.info "finished Traject::Indexer#process: #{count} records in #{'%.3f' % elapsed} seconds; #{'%.1f' % avg_rps} records/second overall."

    if writer.respond_to?(:skipped_record_count) && writer.skipped_record_count > 0
      logger.error "Traject::Indexer#process returning 'false' due to #{writer.skipped_record_count} skipped records."
      return false
    end

    return true
  end

  def completed?
    @completed
  end

  # Instance variable readers and writers are not generally re-usble.
  # The writer may have been closed. The reader does it's thing and doesn't
  # rewind. If we're completed, as a sanity check don't let someone do
  # something with the indexer that uses the reader or writer and isn't gonna work.
  protected def check_uncompleted
    if completed?
      raise CompletedStateError.new("This Traject::Indexer has been completed, and it's reader and writer are not in a usable state")
    end
  end

  # Closes the writer (which may flush/save/finalize buffered records),
  # and calls run_after_processing_steps
  def complete
    writer.close if writer.respond_to?(:close)
    run_after_processing_steps

    # after an indexer has been completed, it is not really usable anymore,
    # as the writer has been closed.
    @completed = true
  end

  def run_after_processing_steps
    @after_processing_steps.each do |step|
      begin
        step.execute
      rescue StandardError => e
        logger.fatal("Unexpected exception #{e} when executing #{step}")
        raise e
      end
    end
  end

  # A light-weight process method meant for programmatic use, generally
  # intended for only a "few" (not milliions) of records.
  #
  # It does _not_ use instance-configured reader or writer, instead taking
  # a source/reader and destination/writer as arguments to this call.
  #
  # The reader can be anything that has an #each returning source
  # records. This includes an ordinary array of source records, or any
  # traject Reader.
  #
  # The writer can be anything with a #put method taking a Traject::Indexer::Context.
  # For convenience, see the Traject::ArrayWriter that just collects output in an array.
  #
  # Return value of process_with is the writer passed as second arg, for your convenience.
  #
  # This does much less than the full #process method, to be more flexible
  # and make fewer assumptions:
  #
  #  * Will never use any additional threads (unless writer does). Wrap in your own threading if desired.
  #  * Will not do any standard logging or progress bars, regardless of indexer settings.
  #    Log yourself if desired.
  #  * Will _not_ call any `after_processing` steps. Call yourself with `indexer.run_after_processing_steps` as desired.
  #  * WILL by default call #close on the writer, IF the writer has a #close method.
  #    pass `:close_writer => false` to not do so.
  #  * exceptions will just raise out, unless you pass in a rescue: option, value is a proc/lambda
  #    that will receive two args, context and exception. If the rescue proc doesn't re-raise,
  #    `process_with` will continue to process subsequent records.
  #
  # @example
  #     array_writer_instance = indexer.process_with([record1, record2], Traject::ArrayWriter.new)
  #
  # @example With a block, in addition to or instead of a writer.
  #
  #     indexer.process_with([record]) do |context|
  #       do_something_with(context.output_hash)
  #     end
  #
  # @param source [#each]
  # @param destination [#put]
  # @param close_writer whether the destination should have #close called on it, if it responds to.
  # @param rescue_with [Proc] to call on errors, taking two args: A Traject::Indexer::Context and an exception.
  #   If nil (default), exceptions will be raised out. If set, you can raise or handle otherwise if you like.
  # @param on_skipped [Proc] will be called for any skipped records, with one arg Traject::Indexer::Context
  def process_with(source, destination = nil, close_writer: true, rescue_with: nil, on_skipped: nil)
    unless destination || block_given?
      raise ArgumentError, "Need either a second arg writer/destination, or a block"
    end

    settings.fill_in_defaults!

    position = 0
    input_name = Traject::Util.io_name(source)
    source.each do |record |
      begin
        position += 1

        context = Context.new(
            :source_record          => record,
            :source_record_id_proc  => source_record_id_proc,
            :settings               => settings,
            :position               => position,
            :position_in_input      => (position if input_name),
            :logger                 => logger
        )

        map_to_context!(context)

        if context.skip?
          on_skipped.call(context) if on_skipped
        else
          destination.put(context) if destination
          yield(context) if block_given?
        end
      rescue StandardError => e
        if rescue_with
          rescue_with.call(context, e)
        else
          raise e
        end
      end
    end

    if close_writer && destination.respond_to?(:close)
      destination.close
    end

    return destination
  end

  # Log that the current record is being skipped, using
  # data in context.position and context.skipmessage
  def log_skip(context)
    logger.debug "Skipped record #{context.record_inspect}: #{context.skipmessage}"
  end

  def reader_class
    unless defined? @reader_class
      reader_class_name = settings["reader_class_name"]

      @reader_class = qualified_const_get(reader_class_name)
    end
    return @reader_class
  end

  def writer_class
    writer.class
  end

  # Instantiate a Traject Reader, using class set
  # in #reader_class, initialized with io_stream passed in
  def reader!(io_stream)
    return reader_class.new(io_stream, settings.merge("logger" => logger))
  end

  # Instantiate a Traject Writer, suing class set in #writer_class
  def writer!
    writer_class = @writer_class || qualified_const_get(settings["writer_class_name"])
    writer_class.new(settings.merge("logger" => logger))
  end

  def writer
    @writer ||= settings["writer"] || writer!
  end


  # Raised by #load_config_file when config file can not
  # be processed.
  #
  # The exception #message includes an error message formatted
  # for good display to the developer, in the console.
  #
  # Original exception raised when processing config file
  # can be found in #original. Original exception should ordinarily
  # have a good stack trace, including the file path of the config
  # file in question.
  #
  # Original config path in #config_file, and line number in config
  # file that triggered the exception in #config_file_lineno (may be nil)
  #
  # A filtered backtrace just DOWN from config file (not including trace
  # from traject loading config file itself) can be found in
  # #config_file_backtrace
  class ConfigLoadError < StandardError
    # We'd have #cause in ruby 2.1, filled out for us, but we want
    # to work before then, so we use our own 'original'
    attr_reader :original, :config_file, :config_file_lineno, :config_file_backtrace

    def initialize(config_file_path, original_exception)
      @original              = original_exception
      @config_file           = config_file_path
      @config_file_lineno    = Traject::Util.backtrace_lineno_for_config(config_file_path, original_exception)
      @config_file_backtrace = Traject::Util.backtrace_from_config(config_file_path, original_exception)
      message                = "Error loading configuration file #{self.config_file}:#{self.config_file_lineno} #{original_exception.class}:#{original_exception.message}"

      super(message)
    end
  end


end
