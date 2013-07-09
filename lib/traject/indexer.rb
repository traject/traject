require 'hashie'
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
#  1) Has a one-argument initializer taking a Settings hash. 
#  2) Responds to a one argument #put method, where the argument is
#     a hash of mapped keys/values. The writer should write them
#     to the appropriate place. 
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
  attr_writer :reader_class, :writer_class

  def initialize
    @settings = Settings.new(self.class.default_settings)
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

  # Used to define an indexing mapping. 
  def to_field(field_name, aLambda = nil, &block)
    @index_steps << {
      :field_name => field_name.to_s,
      :lambda => aLambda,
      :block  => block
    }
  end

  # Processes a single record, according to indexing rules
  # set up in this Indexer. Returns a hash whose values are
  # Arrays, and keys are strings. 
  def map_record(record)
    context = Context.new(:source_record => record, :settings => settings)

    @index_steps.each do |index_step|
      accumulator = []
      field_name  = index_step[:field_name]
      
      # Might have a lambda arg AND a block, we execute in order,
      # with same accumulator.
      [index_step[:lambda], index_step[:block]].each do |aProc|
        if aProc
          case aProc.arity
          when 1 then aProc.call(record)
          when 2 then aProc.call(record, accumulator)
          else        aProc.call(record, accumulator, context)
          end
        end
      end

      (context.output_hash[field_name] ||= []).concat accumulator      
    end

    return context.output_hash
  end

  # Processes a stream of records, reading from the configured Reader,
  # mapping according to configured mapping rules, and then writing
  # to configured Writer. 
  def process(io_stream)
    reader = self.reader!(io_stream)
    writer = self.writer!

    reader.each do |record|
      writer.put map_record(record)
    end
  end

  def reader_class
    unless defined? @reader_class
      @reader_class = qualified_const_get(settings["reader_class_name"])
    end
    return @reader_class
  end

  def writer_class
    unless defined? @reader_class
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
    return writer_class.new(settings)
  end

  def self.default_settings
    {
      "reader_class_name" => "Traject::MarcReader",
      "writer_class_name" => "Traject::JsonWriter"
    }
  end



  # Enhanced with a few features from Hashie, to make it for
  # instance string/symbol indifferent
  class Settings < Hash
    include Hashie::Extensions::MergeInitializer # can init with hash
    include Hashie::Extensions::IndifferentAccess

    # Hashie bug Issue #100 https://github.com/intridea/hashie/pull/100
    alias_method :store, :indifferent_writer
  end

  # Represents the context of a specific record being indexed, passed
  # to indexing logic blocks
  class Traject::Indexer::Context
    def initialize(hash_init = {})
      # TODO, argument checking for required args?

      self.clipboard   = {}
      self.output_hash = {}

      hash_init.each_pair do |key, value|
        self.send("#{key}=", value)
      end
    end

    attr_accessor :clipboard
    attr_accessor :source_record
    attr_accessor :settings
    attr_accessor :output_hash
  end

  protected
  # From http://redcorundum.blogspot.com/2006/05/kernelqualifiedconstget.html
  def qualified_const_get(str)
    path = str.to_s.split('::')
    from_root = path[0].empty?
    if from_root
      from_root = []
      path = path[1..-1]
    else
      start_ns = ((Class === self)||(Module === self)) ? self : self.class
      from_root = start_ns.to_s.split('::')
    end
    until from_root.empty?
      begin
        return (from_root+path).inject(Object) { |ns,name| ns.const_get(name) }
      rescue NameError
        from_root.delete_at(-1)
      end
    end
    path.inject(Object) { |ns,name| ns.const_get(name) }
  end

end
  