require 'hashie'
require 'yell'

require 'traject'
require 'traject/qualified_const_get'
require 'traject/marc_reader'
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
#     a hash of mapped keys/values. The writer should write them
#     to the appropriate place.
#  3) Responds to a #close method, called when we're done.
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
  include Traject::QualifiedConstGet

  attr_writer :reader_class, :writer_class

  # For now we hard-code these basic macro's included
  # TODO, make these added with extend per-indexer,
  # added by default but easily turned off (or have other
  # default macro modules provided)
  include Traject::Macros::Marc21
  include Traject::Macros::Basic


  def initialize
    @settings = Settings.new
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
    if field_name.nil? || field_name.empty?
      raise ArgumentError.new("to_field requires a non-blank first argument, field name")
    end
    [aLambda, block].each do |proc|
      # allow negative arity, meaning variable/optional, trust em on that. 
      # but for positive arrity, we need 2 or 3 args
      if proc && (proc.arity == 1 || proc.arity > 3)
        raise ArgumentError.new("block/proc given to to_field needs 2 or 3 arguments: #{proc}")
      end
    end


    @index_steps << {
      :field_name => field_name.to_s,
      :lambda => aLambda,
      :block  => block
    }
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
      accumulator = []
      field_name  = index_step[:field_name]
      context.field_name = field_name

      # Might have a lambda arg AND a block, we execute in order,
      # with same accumulator.
      [index_step[:lambda], index_step[:block]].each do |aProc|
        if aProc
          case aProc.arity
          when 1 then aProc.call(context.source_record)
          when 2 then aProc.call(context.source_record, accumulator)
          else        aProc.call(context.source_record, accumulator, context)
          end
        end

      end

      (context.output_hash[field_name] ||= []).concat accumulator
      context.field_name = nil
    end

    return context
  end

  # Processes a stream of records, reading from the configured Reader,
  # mapping according to configured mapping rules, and then writing
  # to configured Writer.
  def process(io_stream)
    settings.fill_in_defaults!

    count      =       0
    start_time = Time.now
    logger.info "beginning Indexer#process with settings: #{settings.inspect}"

    reader = self.reader!(io_stream)
    writer = self.writer!

    logger.info "   with reader: #{reader} and writer: #{writer}"

    reader.each do |record|
      count += 1

      context = Context.new(:source_record => record, :settings => settings, :position => count)
      map_to_context!(context)
      writer.put context.output_hash
    end
    writer.close if writer.respond_to?(:close)

    elapsed        = Time.now - start_time
    avg_rps        = (count / elapsed)
    logger.info "finished Indexer#process: #{count} records in #{'%.3f' % elapsed} seconds; #{'%.1f' % avg_rps} records/second overall."
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
    return reader_class.new(io_stream, settings)
  end

  # Instantiate a Traject Writer, suing class set in #writer_class
  def writer!
    return writer_class.new(settings.merge("logger" => logger))
  end


  # Enhanced with a few features from Hashie, to make it for
  # instance string/symbol indifferent
  #
  # #provide(key, value) is added, to do like settings[key] ||= value,
  # set only if not already set (but unlike ||=, nil or false can count as already set)
  #
  # Also has an interesting 'defaults' system, meant to play along
  # with configuration file 'provide' statements. There is a built-in hash of
  # defaults, which will be lazily filled in if accessed and not yet
  # set. (nil can count as set, though!).  If they haven't been lazily
  # set yet, then #provide will still fill them in. But you can also call
  # fill_in_defaults! to fill all defaults in, if you know configuration
  # files have all been loaded, and want to fill them in for inspection.
  class Settings < Hash
    include Hashie::Extensions::MergeInitializer # can init with hash
    include Hashie::Extensions::IndifferentAccess

    # Hashie bug Issue #100 https://github.com/intridea/hashie/pull/100
    alias_method :store, :indifferent_writer

    def initialize(*args)
      super
      self.default_proc = lambda do |hash, key|
        if self.class.defaults.has_key?(key)
          return hash[key] = self.class.defaults[key]
        else
          return nil
        end
      end
    end

    # a cautious store, which only saves key=value if
    # there was not already a value for #key. Can be used
    # to set settings that can be overridden on command line,
    # or general first-set-wins settings.
    def provide(key, value)
      unless has_key? key
        store(key, value)
      end
    end

    # reverse_merge copied from ActiveSupport, pretty straightforward,
    # modified to make sure we return a Settings
    def reverse_merge(other_hash)
      self.class.new(other_hash).merge(self)
    end

    def reverse_merge!(other_hash)
      replace(reverse_merge(other_hash))
    end

    def fill_in_defaults!
      self.reverse_merge!(self.class.defaults)
    end

    def self.defaults
      @@defaults ||= {
      "reader_class_name" => "Traject::MarcReader",
      "writer_class_name" => "Traject::SolrJWriter",
      "marc_source.type" => "binary",
      "marc4j_reader.permissive" => true,
      "marc4j_reader.source_encoding" => "MARC8",
      "solrj_writer.batch_size" => 100
      }
  end

  end

  # Represents the context of a specific record being indexed, passed
  # to indexing logic blocks
  #
  class Traject::Indexer::Context
    def initialize(hash_init = {})
      # TODO, argument checking for required args?

      self.clipboard   = {}
      self.output_hash = {}

      hash_init.each_pair do |key, value|
        self.send("#{key}=", value)
      end
    end

    attr_accessor :clipboard, :output_hash
    attr_accessor :field_name, :source_record, :settings
    # 1-based position in stream of processed records. 
    attr_accessor :position
  end
end
