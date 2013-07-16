require 'traject/marc_extractor'

module Traject::Macros
  # Some of these may be generic for any MARC, but we haven't done
  # the analytical work to think it through, some of this is
  # def specific to Marc21.
  module Marc21

    # A combo function macro that will extract data from marc according to a string
    # field/substring specification, then apply various optional post-processing to it too.
    #
    # First argument is a string spec suitable for the MarcExtractor, see
    # MarcExtractor::parse_string_spec.
    #
    # Second arg is optional options, including options valid on MarcExtractor.new,
    # and others. (TODO)
    #
    # Examples:
    #
    # to_field("title"), extract_marc("245abcd", :trim_punctuation => true)
    # to_field("id"),    extract_marc("001", :first => true)
    # to_field("geo"),   extract_marc("040a", :seperator => nil, :translation_map => "marc040")
    def extract_marc(spec, options = {})
      only_first = options.delete(:first)

      lambda do |record, accumulator, context|
        accumulator.concat Traject::MarcExtractor.extract_by_spec(record, spec, options)

        accumulator.first! if only_first
      end
    end

  end
end