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
      only_first        = options.delete(:first)
      trim_punctuation  = options.delete(:trim_punctuation)

      lambda do |record, accumulator, context|
        accumulator.concat Traject::MarcExtractor.extract_by_spec(record, spec, options)

        # yeah, kind of esoteric, sorry. If ruby had an array.first! mutator, we'd use it.
        accumulator.slice!(1, accumulator.length) if only_first

        # map

        if trim_punctuation
          accumulator.collect! {|s| Marc21.trim_punctuation(s)}
        end
      end
    end


    # Trims punctuation mostly from end, and occasionally from beginning
    # of string. Not nearly as complex logic as SolrMarc's version, just
    # pretty simple.
    #
    # Removes
    # * trailing: comma, slash, semicolon, colon (possibly followed by whitespace)
    # * trailing period if it is preceded by at least three letters (possibly followed by whitespace)
    # * single square bracket characters if they are the start and/or end
    #   chars and there are no internal square brackets.
    #
    # Returns altered string, doesn't change original arg.
    def self.trim_punctuation(str)
      str = str.sub(/[ ,\/;:] *\Z/, '')
      str = str.sub(/(\w\w\w)\. *\Z/, '\1')
      str = str.sub(/\A\[?([^\[\]]+)\]?\Z/, '\1')
      return str
    end

  end
end