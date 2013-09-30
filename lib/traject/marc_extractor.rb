module Traject
  # MarcExtractor is a class for extracting lists of strings from a MARC::Record,
  # according to specifications. See #parse_string_spec for description of string
  # string arguments used to specify extraction. See #initialize for options
  # that can be set controlling extraction.
  #
  # Examples:
  #
  #    array_of_stuff   = MarcExtractor.new("001:245abc:700a").extract(marc_record)
  #    values           = MarcExtractor.new("245a:245abc").extract_marc(marc_record)
  #    seperated_values = MarcExtractor.new("020a:020z").extract(marc_record)
  #
  # == Subfield concatenation
  #
  # Normally, for a spec including multiple subfield codes, multiple subfields
  # from the same MARC field will be concatenated into one string separated by spaces:
  #
  #    600 a| Chomsky, Noam x| Philosophy.
  #    600 a| Chomsky, Noam x| Political and social views.
  #    MarcExtractor.new("600ax").extract(record)
  #    # results in two values sent to Solr: 
  #    "Chomsky, Noam Philosophy."
  #    "Chomsky, Noam Political and social views."
  #
  # You can turn off this concatenation and leave individual subfields in seperate
  # strings by setting the `separator` option to nil:
  #
  #    MarcExtractor.new("600ax", :separator => nil).extract(record)
  #    # Results in four values being sent to Solr (or 3 if you de-dup):
  #    "Chomksy, Noam"
  #    "Philosophy."
  #    "Chomsky, Noam"
  #    "Political and social views."
  #
  # However, **the default is different for specifications with only a single
  # subfield**, these are by default kept seperated:
  #
  #    020 a| 285197145X a| 9782851971456
  #    MarcExtractor.new("020a:020z").extract(record)
  #    # two seperate strings sent to Solr:
  #    "285197145X"
  #    "9782851971456"
  #
  # For single subfield specifications, you force concatenation by
  # repeating the subfield specification:
  #
  #    MarcExtractor.new("020aa:020zz").extract(record)
  #    # would result in a single string sent to solr for
  #    # the single field, by default space-separated:
  #    "285197145X 9782851971456"
  #
  # == Note on Performance and MarcExtractor creation and reuse
  #
  # A MarcExtractor is somewhat expensive to create, and has been shown in profiling/
  # benchmarking to be a bottleneck if you end up creating one for each marc record
  # processed.  Instead, a single MarcExtractor should be created, and re-used
  # per MARC record.
  #
  # If you are creating a traject 'macro' method, here's one way to do that,
  # capturing the MarcExtractor under closure:
  #
  #    def some_macro(spec, other_args, whatever)
  #      extractor = MarcExtractor.new( spec )
  #      # ...
  #      return lambda do |record, accumulator, context|
  #         #...
  #         accumulator.concat extractor.extract(record)
  #         #...
  #      end
  #    end
  #
  # In other cases, you may find it convenient to improve performance by
  # using the MarcExtractor#cached method, instead of MarcExtractor#new, to
  # lazily create and then re-use a MarcExtractor object with
  # particular initialization arguments.
  class MarcExtractor
    attr_accessor :options, :spec_hash

    # Take a hash that's the output of #parse_string_spec, return
    # an array of strings extracted from a marc record accordingly
    #
    # Second arg can either be a string specification that will be passed
    # to MarcExtractor.parse_string_spec, or a Hash that's
    # already been created by it.
    #
    # options:
    #
    # [:separator]  default ' ' (space), what to use to separate
    #               subfield values when joining strings
    #
    # [:alternate_script] default :include, include linked 880s for tags
    #                     that match spec. Also:
    #                     * false => do not include.
    #                     * :only => only include linked 880s, not original
    def initialize(spec, options = {})
      self.options = {
        :separator => ' ',
        :alternate_script => :include
      }.merge(options)

      self.spec_hash = spec.kind_of?(Hash) ? spec : self.class.parse_string_spec(spec)


      # Tags are "interesting" if we have a spec that might cover it
      @interesting_tags_hash = {}

      # By default, interesting tags are those represented by keys in spec_hash.
      # Add them unless we only care about alternate scripts.
      unless options[:alternate_script] == :only
        self.spec_hash.keys.each {|tag| @interesting_tags_hash[tag] = true}
      end

      # If we *are* interested in alternate scripts, add the 880
      if options[:alternate_script] != false
        @interesting_tags_hash['880'] = true
      end
    end

    # Takes the same arguments as MarcExtractor.new, but will re-use an existing
    # cached MarcExtractor already created with given initialization arguments,
    # if available.
    #
    # This can be used to increase performance of indexing routines, as
    # MarcExtractor creation has been shown via profiling/benchmarking
    # to be expensive.
    #
    # Cache is thread-local, so should be thread-safe.
    #
    # You should _not_ modify the state of any MarcExtractor retrieved
    # via cached, as the MarcExtractor will be re-used and shared (possibly
    # between threads even!). We try to use ruby #freeze to keep you from doing so,
    # although if you try hard enough you can surely find a way to do something
    # you shouldn't.
    #
    #    extractor = MarcExtractor.cached("245abc:700a", :separator => nil)
    def self.cached(*args)
      cache = (Thread.current[:marc_extractor_cached] ||= Hash.new)
      extractor = (cache[args] ||= begin
        ex = Traject::MarcExtractor.new(*args).freeze
        ex.options.freeze
        ex.spec_hash.freeze
        ex
      end)

      return extractor
    end

    # Check to see if a tag is interesting (meaning it may be covered by a spec
    # and the passed-in options about alternate scripts)

    def interesting_tag?(tag)
      return @interesting_tags_hash.include?(tag)
    end


    # Converts from a string marc spec like "245abc:700a" to a nested hash used internally
    # to represent the specification.
    #
    # a String specification is a string (or array of strings) of form:
    #  {tag}{|indicators|}{subfields} separated by colons
    # tag is three chars (usually but not neccesarily numeric),
    # indicators are optional two chars enclosed in pipe ('|') characters,
    # subfields are optional list of chars (alphanumeric)
    #
    # indicator spec must be two chars, but one can be * meaning "don't care".
    # space to mean 'blank'
    #
    # "245|01|abc65:345abc:700|*5|:800"
    #
    # Or, for control (fixed) fields (ordinarily fields 001-010), you can include a byte slice specification,
    # but can NOT include subfield or indicator specifications. Plus can use special tag "LDR" for
    # the marc leader. (TODO)
    #
    #  "008[35-37]:LDR[5]"
    #  => bytes 35-37 inclusive of field 008, and byte 5 of the marc leader.
    #
    # Returns a nested hash whose keys are tags and whose value is an array
    # of hash structures indicating what indicators and subfields (or
    # byte-offsets for control fields) are needed, e.g.
    #
    # '245|1*|a:245ab:110:008[15-17]:008[17]' would give us
    #
    # {
    #   '245' => [
    #     {:indicators => ['1', nil], :subfields=>['a']},
    #     {:subfields => ['a', 'b']}
    #    ]
    #    '110' => [{}] # all subfields, indicators don't matter
    #    '008' => [
    #      {:bytes => (15..17)}
    #      {:bytes => 17}
    #    ]
    # }
    #
    # * subfields and indicators can only be provided for marc data/variable fields
    # * byte slice can only be provided for marc control fields (generally tags less than 010)
    #
    # See tests for more examples.
    def self.parse_string_spec(spec_string)
      hash = {}
      spec_strings = spec_string.is_a?(Array) ? spec_string.map{|s| s.split(/\s*:\s*/)}.flatten : spec_string.split(/s*:\s*/)

      spec_strings.each do |part|
        if (part =~ /\A([a-zA-Z0-9]{3})(\|([a-z0-9\ \*]{2})\|)?([a-z0-9]*)?\Z/)
          # variable field
          tag, indicators, subfields = $1, $3, $4

          hash[tag] ||= []
          spec = Spec.new

          if subfields and !subfields.empty?
            spec.subfields = subfields.split('')
          end

          if indicators
           spec.indicators = [ (indicators[0] if indicators[0] != "*"), (indicators[1] if indicators[1] != "*") ]
          end

          hash[tag] << spec
          
        elsif (part =~ /\A([a-zA-Z0-9]{3})(\[(\d+)(-(\d+))?\])\Z/) # "005[4-5]"
          tag, byte1, byte2 = $1, $3, $5
          hash[tag] ||= []
          spec = Spec.new

          if byte1 && byte2
            spec.bytes = ((byte1.to_i)..(byte2.to_i))
          elsif byte1
           spec.bytes = byte1.to_i
          end
          
          hash[tag] << spec
        else
          raise ArgumentError.new("Unrecognized marc extract specification: #{part}")
        end
      end

      return hash
    end


    # Returns array of strings, extracted values. Maybe empty array.
    def extract(marc_record)
      results = []

      self.each_matching_line(marc_record) do |field, spec|
        if control_field?(field)
          results << (spec.bytes ? field.value.byteslice(spec.bytes) : field.value)
        else
          results.concat collect_subfields(field, spec)
        end
      end

      return results
    end

    # Yields a block for every line in source record that matches
    # spec. First arg to block is MARC::DataField or ControlField, second
    # is the MarcExtractor::Spec that it matched on. May take account
    # of options such as :alternate_script
    #
    # Third (optional) arg to block is self, the MarcExtractor object, useful for custom
    # implementations.
    def each_matching_line(marc_record)
      marc_record.fields(@interesting_tags_hash.keys).each do |field|

        specs = spec_covering_field(field)

        # Don't have a spec that addresses this field? Move on.
        next unless specs

        # Make sure it matches indicators too, spec_covering_field
        # doens't check that.
        
        specs.each do |spec|
          if matches_indicators(field, spec)
            yield(field, spec, self)
          end
        end
      end
    end

    # line each_matching_line, takes a block to process each matching line,
    # but collects results of block into an array -- flattens any subarrays for you!
    #
    # Useful for re-use of this class for custom processing
    #
    # yields the MARC Field, the MarcExtractor::Spec object, the MarcExtractor object. 
    def collect_matching_lines(marc_record)
      results = []
      self.each_matching_line(marc_record) do |field, spec, extractor|
        results.concat [yield(field, spec, extractor)].flatten
      end
      return results
    end


    # Pass in a marc data field and a hash spec, returns
    # an ARRAY of one or more strings, subfields extracted
    # and processed per spec. Takes account of options such
    # as :separator
    #
    # Always returns array, sometimes empty array.
    def collect_subfields(field, spec)
      subfields = field.subfields.collect do |subfield|
        subfield.value if spec.subfields.nil? || spec.subfields.include?(subfield.code)
      end.compact

      return subfields if subfields.empty? # empty array, just return it.

      if options[:separator] && spec.joinable?
        subfields = [subfields.join(options[:separator])]
      end
      
      return subfields
    end



    # Find a spec, if any, covering extraction from this field
    #
    # When given an 880, will return the spec (if any) for the linked tag iff
    # we have a $6 and we want the alternate script.
    #
    # Returns nil if no matching spec is found

    def spec_covering_field(field)
      tag = field.tag

      # Short-circuit the unintersting stuff
      return nil unless interesting_tag?(tag)

      # Due to bug in jruby https://github.com/jruby/jruby/issues/886 , we need
      # to do this weird encode gymnastics, which fixes it for mysterious reasons.

      if tag == "880" && field['6']
        tag = field["6"].encode(field["6"].encoding).byteslice(0,3)
      end

      # Take the resulting tag and get the spec from it (or the default nil if there isn't a spec for this tag)
      spec = self.spec_hash[tag]
    end


    def control_field?(field)
      # should the MARC gem have a more efficient way to do this,
      # define #control_field? on both ControlField and DataField?
      return field.kind_of? MARC::ControlField
    end

    # a marc field, and an individual spec hash, {:subfields => array, :indicators => array}
    def matches_indicators(field, spec)
      return true if spec.indicators.nil?

      return (spec.indicators[0].nil? || spec.indicators[0] == field.indicator1) &&
        (spec.indicators[1].nil? || spec.indicators[1] == field.indicator2)
    end

    # Represents a single specification for extracting certain things
    # from a marc field, like "600abc" or "600|1*|x". 
    #
    # Does not actually include the tag at present, becuase not neccesary
    # to do the extraction -- tag is implicit in the overall spec_hash 
    # with tag => [spec1, spec2]
    class Spec
      attr_accessor :subfields, :indicators, :bytes

      def initialize(hash = {})
        hash.each_pair do |key, value|
          self.send("#{key}=", value)
        end
      end

    
      #  Should subfields extracted by joined, if we have a seperator?
      #  * '630' no subfields specified => join all subfields
      #  * '630abc' multiple subfields specified = join all subfields
      #  * '633a' one subfield => do not join, return one value for each $a in the field
      #  * '633aa' one subfield, doubled => do join after all, will return a single string joining all the values of all the $a's.
      #
      # Last case is handled implicitly at the moment when subfields == ['a', 'a']
      def joinable?
        (self.subfields.nil? || self.subfields.size != 1)
      end

      def ==(spec)
        return false unless spec.kind_of?(Spec)

        return (self.subfields == spec.subfields) && 
          (self.indicators == spec.indicators) &&
          (self.bytes == spec.bytes)
      end
    end

  end
end
