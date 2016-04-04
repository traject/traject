require 'yaml'
require 'dot-properties'


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
  # yaml, or java .properties file (not all .properties features may
  # be supported, we use dot-properties gem for reading)
  #
  # traject's `extract_marc` macro allows you to specify a :translation_map=>filename argument
  # that will automatically find and use a translation map on the resulting data:
  #
  #     extract_marc("040a", :translation_map => "languages")
  #
  # Or you can always create one yourself and use it how you like:
  #
  #     map = TranslationMap.new("languages")
  #
  # In either case, TranslationMap will look for a file named, in that example,
  # `languages.rb` or `languages.yaml` or `languages.properties`,
  # somewhere in the ruby $LOAD_PATH in a `/translation_maps` subdir.
  #
  # * Also looks for "/translation_maps" subdir in load paths, so
  #   for instance you can have a gem that keeps translation maps
  #   in ./lib/translation_maps, and it Just Works.
  #
  # * Note you do NOT supply the .rb, .yaml, or .properties suffix yourself,
  #  it'll use whichever it finds (allows calling code to not care which is used).
  #
  # Ruby files just need to have their last line eval to a hash. They file
  # will be run through `eval`, don't do it with untrusted content (naturally)
  #
  # You can also pass in a Hash for consistency to TranslationMap.new, although
  # I don't know why you'd want to.
  #
  # ## Special default handling
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
  # ## Output: String or array of strings
  #
  # The output can be a string or an array of strings, or nil.  It should not be anything else.
  # When used with the #translate_array! method, one string can be replaced by multiple values
  # (array of strings) or removed (nil)
  #
  # There's no way to specify multiple return values in a .properties, use .yaml or .rb for that.
  #
  # ## Caching
  #
  # Lookup and loading of configuration files will be cached, for efficiency.
  # You can reset with `TranslationMap.reset_cache!`
  #
  # ## YAML example:
  #
  #     key: value
  #     key2: value2 multiple words fine
  #     key2b: "Although you can use quotes if you want: Or need."
  #     key3:
  #       - array
  #       - of
  #       - values look like this
  #
  # ## Alternatives
  # `Traject::TranslationMap` provides an easy way to deal with the most common translation case:
  # simple key-value stores with optional default values.
  #
  # If you need more complex translation, you can simply use `#map!`
  # or its kin to work on the `accumulator` in a block
  #
  #
  #
  #     # get a lousy language detection of any vernacular title
  #     require 'whatlanguage'
  #     wl = WhatLanguage.new(:all)
  #     to_field 'vernacular_langauge', extract_marc('245', :alternate_script=>:only) do |rec, acc|
  #       # accumulator is already filled with the values of any 880s that reference a 245 because
  #       # of the call to #extract_marc
  #       acc.map! {|x| wl.language(x) }
  #       acc.uniq!
  #     end
  # Within the block, you may also be interested in using:
  # * a case-insentive hash, perhaps like [this one](https://github.com/junegunn/insensitive_hash)
  # * a [MatchMap](https://github.com/billdueber/match_map), which implements pattern-matching logic similar to solrmarc's pattern files
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

          if File.exist? rb_file
            found = eval( File.open(rb_file).read , binding, rb_file )
            break
          elsif File.exist? yaml_file
            found = YAML.load_file(yaml_file)
            break
          elsif File.exist? prop_file
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
      elsif defn.kind_of? self.class
        @hash = defn.to_hash
        @default = defn.default
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
      dup = @hash.dup
      dup.delete("__default__")
      dup
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

    # Return a new TranslationMap that results from merging argument on top of self.
    # Can be useful for taking an existing translation map, but merging a few
    # overrides on top.
    #
    #     merged_map = TranslationMap.new(something).merge TranslationMap.new(else)
    #     #...
    #     merged_map.translate_array(something) # etc
    #
    # If a default is set in the second map, it will merge over the first too.
    #
    # You can also pass in a plain hash as an arg, instead of an existing TranslationMap:
    #
    #     TranslationMap.new(something).merge("overridden_key" => "value", "a" => "")
    def merge(other_map)
      default = other_map.default || self.default
      TranslationMap.new(self.to_hash.merge(other_map.to_hash), :default => default)
    end

    class NotFound < Exception
      def initialize(path)
        super("No translation map definition file found at 'translation_maps/#{path}.[rb|yaml|properties]' in load path: #{$LOAD_PATH}")
      end
    end

    protected

    # We use dot-properties gem for reading .properties files,
    # return a hash.
    def self.read_properties(file_name)
      return DotProperties.load(file_name).to_h
    end

  end
end
