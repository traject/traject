require 'traject/marc_extractor'
require 'traject/translation_map'
require 'base64'
require 'json'

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
    # * :first => true: take only first value
    # * :translation_map => String: translate with named translation map looked up in load
    #       path, uses Tranject::TranslationMap.new(translation_map_arg)
    # * :trim_punctuation => true; trims leading/trailing punctuation using standard algorithms that
    #     have shown themselves useful with Marc, using Marc21.trim_punctuation
    # * :default => String: if otherwise empty, add default value
    #
    # Examples:
    #
    # to_field("title"), extract_marc("245abcd", :trim_punctuation => true)
    # to_field("id"),    extract_marc("001", :first => true)
    # to_field("geo"),   extract_marc("040a", :seperator => nil, :translation_map => "marc040")
    def extract_marc(spec, options = {})
      only_first              = options.delete(:first)
      trim_punctuation        = options.delete(:trim_punctuation)
      default_value           = options.delete(:default)

      # We create the TranslationMap and the MarcExtractor here
      # on load, so the lambda can just refer to already created
      # ones, and not have to create a new one per-execution.
      #
      # Benchmarking shows for MarcExtractor at least, there is
      # significant performance advantage. 

      if translation_map_arg  = options.delete(:translation_map)
        translation_map = Traject::TranslationMap.new(translation_map_arg)
      end

      extractor = Traject::MarcExtractor.new(spec, options)

      lambda do |record, accumulator, context|
        accumulator.concat extractor.extract(record)

        if only_first
          Marc21.first! accumulator
        end

        if translation_map
          translation_map.translate_array! accumulator
        end

        if trim_punctuation
          accumulator.collect! {|s| Marc21.trim_punctuation(s)}
        end

        if default_value && accumulator.empty?
          accumulator << default_value
        end
      end
    end

    # Serializes complete marc record to a serialization format.
    # required param :format,
    # serialize_marc(:format => :binary)
    #
    # formats:
    # [xml] MarcXML
    # [json] marc-in-json (http://dilettantes.code4lib.org/blog/2010/09/a-proposal-to-serialize-marc-in-json/)
    # [binary] Standard ISO 2709 binary marc. By default WILL be base64-encoded,
    #          assumed destination a solr 'binary' field.
    #          * add option `:binary_escape => false` to do straight binary -- unclear
    #          what Solr's documented behavior is when you do this, and add a string
    #          with binary control chars to solr. May do different things in diff
    #          Solr versions, including raising exceptions.
    #          * add option `:allow_oversized => true` to pass that flat
    #          to the MARC::Writer. Oversized records will then still be
    #          serialized, with certain header bytes filled with ascii 0's
    #          -- technically illegal MARC, but can still be read by
    #          ruby MARC::Reader in permissive mode.
    def serialized_marc(options)
      format        = options[:format].to_s
      binary_escape = (options[:binary_escape] != false)

      raise ArgumentError.new("Need :format => [binary|xml|json] arg") unless %w{binary xml json}.include?(format)

      allow_oversized = (options[:allow_oversized] == true)

      lambda do |record, accumulator, context|
        case format
        when "binary"
          binary = MARC::Writer.encode(record, allow_oversized)
          binary = Base64.encode64(binary) if binary_escape
          accumulator << binary
        when "xml"
          # ruby-marc #to_xml returns a REXML object at time of this writing, bah!@
          # call #to_s on it. Hopefully that'll be forward compatible.
          accumulator << record.to_xml.to_s
        when "json"
          accumulator << JSON.dump(record.to_hash)
        end
      end
    end

    # Takes the whole record, by default from tags 100 to 899 inclusive,
    # all subfields, and adds them to output. Subfields in a record are all
    # joined by space by default.
    #
    # options
    # [:from] default 100, only tags >= lexicographically
    # [:to]   default 899, only tags <= lexicographically
    # [:seperator] how to join subfields, default space, nil means don't join
    #
    # All fields in from-to must be marc DATA (not control fields), or weirdness
    #
    # Can always run this thing multiple times on the same field if you need
    # non-contiguous ranges of fields.
    def extract_all_marc_values(options = {})
      options = {:from => "100", :to => "899", :seperator => ' '}.merge(options)

      lambda do |record, accumulator, context|
        record.each do |field|
          next unless field.tag >= options[:from] && field.tag <= options[:to]
          subfield_values = field.subfields.collect {|sf| sf.value}
          next unless subfield_values.length > 0

          if options[:seperator]
            accumulator << subfield_values.join( options[:seperator])
          else
            accumulator.concat subfield_values
          end
        end
      end

    end


    # Trims punctuation mostly from end, and occasionally from beginning
    # of string. Not nearly as complex logic as SolrMarc's version, just
    # pretty simple.
    #
    # Removes
    # * trailing: comma, slash, semicolon, colon (possibly preceded and followed by whitespace)
    # * trailing period if it is preceded by at least three letters (possibly preceded and followed by whitespace)
    # * single square bracket characters if they are the start and/or end
    #   chars and there are no internal square brackets.
    #
    # Returns altered string, doesn't change original arg.
    def self.trim_punctuation(str)
      str = str.sub(/ *[ ,\/;:] *\Z/, '')
      str = str.sub(/ *(\w\w\w)\. *\Z/, '\1')
      str = str.sub(/\A\[?([^\[\]]+)\]?\Z/, '\1')
      return str
    end

    def self.first!(arr)
      # kind of esoteric, but slice used this way does mutating first, yep
      arr.slice!(1, arr.length)
    end

  end
end