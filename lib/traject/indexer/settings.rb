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
  # provide WILL overwrite defaults.
  #
  # Or you can use standard Hash `store` which will overwrite already set values as well
  # as defaults.
  #
  # Has kind of a weird 'defaults' system, where you tell the hash what it's defaults
  # are, but they aren't actually loaded until asked for (or you can call fill_in_defaults!
  # to load em all for inspection), to accomodate the `provide` API, where a caller wants to set
  # only if not already set, but DO overwrite defaults.
  class Settings < Hash
    # Just a hash with indifferent access and hash initializer, to use for
    # our defaults hash.
    class DefaultsHash < Hash
      include Hashie::Extensions::MergeInitializer # can init with hash
      include Hashie::Extensions::IndifferentAccess
    end

    include Hashie::Extensions::MergeInitializer # can init with hash
    include Hashie::Extensions::IndifferentAccess

    def initialize(*args)
      super

      @defaults = {}

      self.default_proc = lambda do |hash, key|
        if @defaults.has_key?(key)
          return hash[key] = @defaults[key]
        else
          return nil
        end
      end

      @defaults_filled = Concurrent::AtomicBoolean.new(false)
    end

    def with_defaults(defaults)
      @defaults = DefaultsHash.new(defaults).freeze
      self
    end

    def keys
      super + @defaults.keys
    end

    # a cautious store, which only saves key=value if
    # there was not already a value for #key. Can be used
    # to set settings that can be overridden on command line,
    # or general first-set-wins settings. DOES set over defaults.
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

    # Normally defaults are filled in on-demand, but you can trigger it here --
    # but if you later try to load traject config, `provide` will no longer
    # overwrite defaults!
    def fill_in_defaults!
      self.reverse_merge!(@defaults)
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
