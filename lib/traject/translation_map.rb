require 'yaml'

module Traject
  # A TranslationMap is basically just something that has a hash-like #[]
  # method to map from input strings to output strings:
  #
  #   translation_map["some_input"] #=> some_output
  #
  # Input is assumed to always be string, output is either string
  # or array of strings.
  #
  # What makes it more useful than a stunted hash is it's ability to load
  # the hash definitions from configuration files, either pure ruby or
  # yaml.
  #
  # TranslationMap.new("dir/some_file")
  #
  # Will look through the entire ruby $LOAD_PATH for either some_file.rb OR
  # some_file.yaml . Note you do NOT supply the ".rb" or ".yaml" suffix yourself,
  # it'll use whichever it finds (allows calling code to not care which is used).
  #
  # Ruby files just need to have their last line eval to a hash. They file
  # will be run through `eval`, don't do it with untrusted content (naturally)
  #
  # You can also pass in a Hash for consistency to TranslationMap.new, although
  # I don't know why you'd want to.
  #
  # == Special default handling
  #
  # The key "__default__" in the hash is treated specially. If set to a string,
  # that string will be returned by the TranslationMap for any input not otherwise
  # included. If set to the special string "__passthrough__", then for input not
  # mapped, the original input string will be returned.
  #
  # This is most useful for YAML definition files, if you are using an actual ruby
  # hash, you could just set the hash to do what you want using Hash#default_proc
  # etc.
  #
  # Or, when calling TranslationMap.new(), you can pass in options over-riding special
  # key too:
  #
  #  TranslationMap.new("something", :default => "foo")
  #  TranslationMap.new("something", :default => :passthrough)
  #
  # == Output: String or array of strings
  #
  # The output can be a string or an array of strings, or nil.  It should not be anything
  # When used with the #translate_array! method, one string can be replaced by multiple values
  # (array of strings) or removed (nil)
  #
  # == Caching
  # Lookup and loading of configuration files will be cached, for efficiency.
  # You can reset with `TranslationMap.reset_cache!`
  #
  # == YAML example:
  #
  #     key: value
  #     key2: value2 multiple words fine
  #     key2b: "Although you can use quotes if you want: Or need."
  #     key3:
  #       - array
  #       - of
  #       - values look like this
  class TranslationMap
    class Cache
      def initialize
        @cached = Hash.new 
      end

      # Returns an actual Hash -- or nil if none found. 
      def lookup(path)
        unless @cached.has_key?(path)
          @cached[path] = _lookup!(path)
        end
        return @cached[path]
      end

      # force lookup, without using cache.
      # used by cache. Returns the actual hash. 
      # Returns nil if none found. 
      # May raise on syntax error in file being loaded. 
      def _lookup!(path)
        found = nil

        $LOAD_PATH.each do |base|
          rb_file = File.join( base, "#{path}.rb"  )
          yaml_file = File.join( base, "#{path}.yaml"  )

          if File.exists? rb_file
            found = eval( File.open(rb_file).read , binding, rb_file )
            break
          elsif File.exists? yaml_file
            found = YAML.load_file(yaml_file)
          end
        end

        return found
      end

    end

    attr_reader :hash
    attr_reader :default

    class << self
      attr_accessor :cache
    end
    self.cache = Cache.new


    def initialize(defn, options = {})
      @default = options[:default]

      if defn.kind_of? Hash
        @hash = defn
      else
        @hash = lookup(defn)
      end
    end

  end
end