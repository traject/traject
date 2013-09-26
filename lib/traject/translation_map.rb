require 'traject'

require 'yaml'


module Traject
  # A TranslationMap is basically just something that has a hash-like #[]
  # method to map from input strings to output strings:
  #
  #    translation_map["some_input"] #=> some_output
  #
  # Input is assumed to always be string, output is either string
  # or array of strings.
  #
  # What makes it more useful than a stunted hash is it's ability to load
  # the hash definitions from configuration files, either pure ruby, 
  # yaml, or java .properties.  (Limited basic .properties, don't try any fancy escaping please,
  # no = or : in key names, no split lines.)
  #
  #     TranslationMap.new("dir/some_file")
  #
  # Will look for a file named `some_file.rb` or `some_file.yaml` or `some_file.properties`, 
  # somewhere in the ruby $LOAD_PATH in a `/translation_maps` subdir. 
  # * Looks for "/translation_maps" subdir in load paths, so
  #   for instance you can have a gem that keeps translation maps
  #   in ./lib/translation_maps, and it Just Works. 
  # * Note you do NOT supply the .rb, .yaml, or .properties suffix yourself,
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
  #    TranslationMap.new("something", :default => "foo")
  #    TranslationMap.new("something", :default => :passthrough)
  #
  # == Output: String or array of strings
  #
  # The output can be a string or an array of strings, or nil.  It should not be anything
  # When used with the #translate_array! method, one string can be replaced by multiple values
  # (array of strings) or removed (nil)
  #
  # There's no way to specify multiple return values in a .properties, use .yaml or .rb for that. 
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
          rb_file = File.join( base,  "translation_maps",  "#{path}.rb"  )
          yaml_file = File.join( base, "translation_maps", "#{path}.yaml"  )
          prop_file = File.join(base, "translation_maps", "#{path}.properties" )

          if File.exists? rb_file
            found = eval( File.open(rb_file).read , binding, rb_file )
            break
          elsif File.exists? yaml_file
            found = YAML.load_file(yaml_file)
            break
          elsif File.exists? prop_file
            found = Traject::TranslationMap.read_properties(prop_file)
            break
          end
        end

        # Cached hash can't be mutated without weird consequences, let's
        # freeze it! 
        found.freeze if found

        return found
      end

      def reset_cache!
        @cached.clear
      end

    end

    attr_reader :hash
    attr_reader :default

    class << self
      attr_accessor :cache
      def reset_cache!
        cache.reset_cache!
      end
    end
    self.cache = Cache.new


    def initialize(defn, options = {})
      if defn.kind_of? Hash
        @hash = defn
      else
        @hash = self.class.cache.lookup(defn)
        raise NotFound.new(defn) if @hash.nil?
      end

      if options[:default]
        @default = options[:default]
      elsif @hash.has_key? "__default__"
        @default = @hash["__default__"]
      end
    end

    def [](key)
      if self.default && (! @hash.has_key?(key))
        if self.default == "__passthrough__"
          return key
        else
          return self.default
        end
      end

      @hash[key]
    end
    alias_method :map, :[]

    # Returns a dup of internal hash, dup so you can modify it
    # if you like. 
    def to_hash
      @hash.dup
    end

    # Run every element of an array through this translation map,
    # return the resulting array. If translation map returns nil,
    # original element will be missing from output. 
    #
    # If an input maps to an array, each element of the array will be flattened
    # into the output. 
    #
    # If an input maps to nil, it will cause the input element to be removed
    # entirely. 
    def translate_array(array)
      array.each_with_object([]) do |input_element, output_array|
        output_element = self.map(input_element)
        if output_element.kind_of? Array
          output_array.concat output_element
        elsif ! output_element.nil?
          output_array << output_element
        end
      end
    end

    def translate_array!(array)
      array.replace( self.translate_array(array))
    end

    class NotFound < Exception
      def initialize(path)
        super("No translation map definition file found at 'translation_maps/#{path}.[rb|yaml|properties]' in load path: #{$LOAD_PATH}")
      end
    end

    protected

    # No built-in way to read java-style .properties, we hack it. 
    # inspired by various hacky things found google ruby java properties parse
    # .properties spec seems to be:
    # http://docs.oracle.com/javase/6/docs/api/java/util/Properties.html#load%28java.io.Reader%29
    #
    # We do NOT handle split lines, don't do that!
    def self.read_properties(file_name)
      hash = {}
      i = 0
      f = File.open(file_name)
      f.each_line do |line|
        i += 1

        line.strip! 

        # skip blank lines
        next if line.empty? 

        # skip comment lines
        next if line =~ /^\s*[!\#].*$/

        if line =~ /\A([^:=]+)[\:\=]\s*(.*)\s*\Z/
          hash[$1.strip] = $2
        else
          raise IOError.new("Can't parse from #{file_name} line #{i}: #{line}")
        end
      end
      f.close

      return hash
    end

  end
end
