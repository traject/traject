

module Traject
  # MarcExtractor is a class for extracting lists of strings from a MARC::Record,
  # according to specifications. See #parse_string_spec for description of string
  # string arguments used to specify extraction. See #initialize for options
  # that can be set controlling extraction.
  #
  # Examples:
  #
  #    array_of_stuff = MarcExtractor.new(marc_record, "001:245abc:700a").extract
  #    values         = MarcExtractor.new(marc_record, "040a", :seperator => nil).extract
  #
  class MarcExtractor
    attr_accessor :options, :marc_record, :spec_hash


    # Convenience method to construct a MarcExtractor object and
    # run extract on it.
    #
    # First arg is a marc record.
    #
    # Second arg is either a string that will be given to parse_string_spec,
    # OR a hash that's the return value of parse_string_spec.
    #
    # Third arg is an optional options hash that will be passed as
    # third arg of MarcExtractor constructor.
    def self.extract_by_spec(marc_record, specification, options = {})
      (raise ArgumentError, "first argument must not be nil") if marc_record.nil?

      Traject::MarcExtractor.new(marc_record, specification, options).extract
    end

    # Take a hash that's the output of #parse_string_spec, return
    # an array of strings extracted from a marc record accordingly
    #
    # Second arg can either be a string specification that will be passed
    # to MarcExtractor.parse_string_spec, or a Hash that's
    # already been created by it.
    #
    # options:
    #
    # [:seperator]  default ' ' (space), what to use to seperate
    #               subfield values when joining strings
    #
    # [:alternate_script] default :include, include linked 880s for tags
    #                     that match spec. Also:
    #                     * false => do not include.
    #                     * :only => only include linked 880s, not original
    def initialize(marc_record, spec, options = {})
      self.options = {
        :seperator => ' ',
        :alternate_script => :include
      }.merge(options)

      self.marc_record = marc_record

      self.spec_hash = spec.kind_of?(Hash) ? spec : self.class.parse_string_spec(spec)
      
      @interesting_tags = self.spec_hash.keys
      @interesting_tags << '880' if options[:alternate_script] != false
    end

    # Converts from a string marc spec like "245abc:700a" to a nested hash used internally
    # to represent the specification.
    #
    # a String specification is a string of form:
    #  {tag}{|indicators|}{subfields} seperated by colons
    # tag is three chars (usually but not neccesarily numeric),
    # indicators are optional two chars prefixed by hyphen,
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
    # Returns a nested hash keyed by tags.
    # { tag => {
    #     :subfields => ['a', 'b', '2'] # actually, a SET. may be empty or nil
    #     :indicators => ['1', '0'] # An array. may be empty or nil; duple, either one can be nil
    #    }
    #}
    # For byte offsets, :bytes => 12 or :bytes => (7..10)
    #
    # * subfields and indicators can only be provided for marc data/variable fields
    # * byte slice can only be provided for marc control fields (generally tags less than 010)
    #
    # See tests for more examples.
    def self.parse_string_spec(spec_string)
      hash = {}

      spec_string.split(":").each do |part|
        if (part =~ /\A([a-zA-Z0-9]{3})(\|([a-z0-9\ \*]{2})\|)?([a-z0-9]*)?\Z/)
          # variable field
          tag, indicators, subfields = $1, $3, $4

          hash[tag] ||= {}

          if subfields
            subfields.each_char do |subfield|
              hash[tag][:subfields] ||= Array.new
              hash[tag][:subfields] << subfield
            end
          end
          if indicators
            hash[tag][:indicators] = [ (indicators[0] if indicators[0] != "*"), (indicators[1] if indicators[1] != "*") ]
          end
        elsif (part =~ /\A([a-zA-Z0-9]{3})(\[(\d+)(-(\d+))?\])\Z/) # "005[4-5]"
          tag, byte1, byte2 = $1, $3, $5
          hash[tag] ||= {}

          if byte1 && byte2
            hash[tag][:bytes] = ((byte1.to_i)..(byte2.to_i))
          elsif byte1
            hash[tag][:bytes] = byte1.to_i
          end
        else
          raise ArgumentError.new("Unrecognized marc extract specification: #{part}")
        end
      end

      return hash
    end


    # Returns array of strings, extracted values. Maybe empty array.
    def extract
      results = []

      self.each_matching_line do |field, spec|
        if control_field?(field)
          results << (spec[:bytes] ? field.value.byteslice(spec[:bytes]) : field.value)
        else
          results.concat collect_subfields(field, spec)
        end
      end

      return results
    end

    # Yields a block for every line in source record that matches
    # spec. First arg to block is MARC::DataField or ControlField, second
    # is the hash specification that it matched on. May take account
    # of options such as :alternate_script
    #
    # Third (optional) arg to block is self, the MarcExtractor object, useful for custom
    # implementations.
    def each_matching_line
      self.marc_record.fields(@interesting_tags).each do |field|
        
        spec = get_matching_spec(field)
                
        # Don't have one? Bail
        next unless spec
        
        # Check it against the indicators if needed; don't if not
        if spec[:indicators]
          if matches_indicators(field, spec)
            yield(field, spec, self)
          end
        else
          yield(field, spec, self)
        end
      end
    end

    # line each_matching_line, takes a block to process each matching line,
    # but collects results of block into an array -- flattens any subarrays for you!
    #
    # Useful for re-use of this class for custom processing
    def collect_matching_lines
      results = []
      self.each_matching_line do |field, spec, extractor|
        results.concat [yield(field, spec, extractor)].flatten
      end
      return results
    end


    # Pass in a marc data field and a hash spec, returns
    # an ARRAY of one or more strings, subfields extracted
    # and processed per spec. Takes account of options such
    # as :seperator
    #
    # Always returns array, sometimes empty array.
    def collect_subfields(field, spec)
      subfields = field.subfields.collect do |subfield|
        subfield.value if spec[:subfields].nil? || spec[:subfields].include?(subfield.code)
      end.compact

      return subfields if subfields.empty? # empty array, just return it.

      return options[:seperator] ? [ subfields.join( options[:seperator]) ] : subfields
    end


    def get_matching_spec(field)
      # Get the tag
      tag = field.tag
      
      # Change the tag to the $6 iff we have an 880 with a $6 and we want the alternate script
      # Note that 880 won't be in @interesting_tag unless options[:alternate_script] != false
      if tag == "880" && field['6']
        tag = field["6"].encode(field["6"].encoding).byteslice(0,3)
      elsif options[:alternate_script] == :only
        # If it's *not* an 880, and we want :only the alternate script, bail
        return nil
      end
      
      # Take the resulting tag and get the spec from it
      spec = self.spec_hash[tag]  
    end
    

    def control_field?(field)
      # should the MARC gem have a more efficient way to do this,
      # define #control_field? on both ControlField and DataField?
      return field.kind_of? MARC::ControlField
    end

    # a marc field, and an individual spec hash, {:subfields => array, :indicators => array}
    def matches_indicators(field, spec)
      return true if spec[:indicators].nil?

      return (spec[:indicators][0].nil? || spec[:indicators][0] == field.indicator1) &&
        (spec[:indicators][1].nil? || spec[:indicators][1] == field.indicator2)
    end
  end
end
