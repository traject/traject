require 'traject/marc_extractor'

module Traject::Macros
  # Some of these may be generic for any MARC, but we haven't done
  # the analytical work to think it through, some of this is
  # def specific to Marc21.
  module Marc21

    # A combo function that will extract data from marc according to a string field/substring
    # spec, then apply various optional post-processing to it too. 
    def extract_marc(spec, options = {})
      lambda do |record, accumulator, context|        
      end
    end

    # a spec is a string of form:
    #  {tag}-{indicators}{subfields} seperated by colons
    # tag is three chars (usually but not neccesarily numeric),
    # indicators are optional two chars prefixed by hyphen,
    # subfields are optional list of chars (alphanumeric)
    #
    # indicator spec must be two chars, but one can be * meaning "don't care".
    # space to mean 'blank'
    #
    # "245-01abc65:345abc:700-*5:800"
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
        if (part =~ /\A([a-zA-Z0-9]{3})(-([a-z0-9\ \*]{2}))?([a-z0-9]*)?\Z/)
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


    # Take a hash that's the output of #parse_string_spec, return
    # an array of strings extracted from a marc record accordingly
    #
    # uses the MarcSpecExtractor helper class
    def self.extract_by_spec(marc_record, spec_hash, options = {})
      (raise IllegalArgument, "first argument must not be nil") if marc_record.nil?

      Traject::MarcExtractor.new(marc_record, spec_hash, options).extract
    end



  end
end