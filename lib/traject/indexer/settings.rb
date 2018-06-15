require 'hashie'
require 'concurrent'

class Traject::Indexer

  # A Hash of settings for a Traject::Indexer, which also ends up passed along
  # to other objects Traject::Indexer interacts with.
  #
  # Enhanced with a few features from Hashie, to make it for
  # instance string/symbol indifferent
  #
  # method #provide(key, value) is added, to do like settings[key] ||= value,
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

    def self.mri_defaults
      {
          # Reader defaults
          "reader_class_name"       => "Traject::MarcReader",
          "marc_source.type"        => "binary",

          # Writer defaults
          "writer_class_name"       => "Traject::SolrJsonWriter",
          "solr_writer.batch_size"  => 100,
          "solr_writer.thread_pool" => 1,

          # Threading and logging
          "processing_thread_pool"  => self.default_processing_thread_pool,
          "log.batch_size.severity" => "info",

          # how to post-process the accumulator
          "allow_nil_values"        => false,
          "allow_duplicate_values"  => true,

          "allow_empty_fields"      => false,
      }
    end

    def self.jruby_defaults
      {
          'reader_class_name'        => "Traject::Marc4JReader",
          'marc4j_reader.permissive' => true
      }
    end


    def self.defaults
      return @@defaults if defined? @@defaults
      default_settings = self.mri_defaults
      if defined? JRUBY_VERSION
        default_settings.merge! self.jruby_defaults
      end

      @@defaults = default_settings
    end

    def inspect
      # Keep any key ending in password out of the inspect
      self.inject({}) do |hash, (key, value)|
        if /password\Z/.match(key)
          hash[key] = "[hidden]"
        else
          hash[key] = value
        end
        hash
      end.inspect
    end

    protected
    def self.default_processing_thread_pool
      if ["jruby", "rbx"].include? ENV["RUBY_ENGINE"]
        [1, Concurrent.processor_count - 1].max
      else
        1
      end
    end

  end
end
