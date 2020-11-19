require 'traject/marc_extractor'
require 'traject/translation_map'
require 'traject/util'
require 'base64'
require 'json'
require 'marc/fastxmlwriter'

module Traject::Macros
  # Some of these may be generic for any MARC, but we haven't done
  # the analytical work to think it through, some of this is
  # def specific to Marc21.
  module Marc21

    # A macro that will extract data from marc according to a string
    # field/substring specification.
    #
    # First argument is a string spec suitable for the MarcExtractor, see
    # Traject::MarcExtractor::Spec.
    #
    # Second arg is optional options, including options valid on MarcExtractor.new,
    # and others. By default, will de-duplicate results, but see :allow_duplicates
    #
    #
    # * :allow_duplicates => boolean, default false, if set to true then will avoid
    #       de-duplicating the result array (array.uniq!)
    #
    # * :separator: (default ' ' (space)), what to use when joining multiple subfield matches from
    #   same field. Set to `nil` to leave them as separate values (which is actually default if only
    #   one subfield is given in spec, like `100a`). See MarcExtractor docs for more info.
    #
    # * :alternate_script: (default true). True, automatically include
    #   'alternate script' MARC 880 linked fields corresponding to matched specifications. `false`, do
    #   not include.  `:only` include _only_ linked 880s corresponding to spec, not base tags.
    #
    # ## Soft-Deprecated options: post-processing transformations
    #
    # These don't produce a deprecation warning and there is no planned horizon for them to go away, but the
    # alternative of using additional transformation macros (from Traject::Macros::Transformation) composed with
    # extract_marc is recommended.
    #
    # * :first => true: take only first value. **Instead**, use `extract_marc(whatever), first_only`
    #
    # * :translation_map => String: translate with named translation map looked up in load
    #       path, uses Tranject::TranslationMap.new(translation_map_arg).
    #       **Instead**, use `extract_marc(whatever), translation_map(translation_map_arg)`
    #
    # * :trim_punctuation => true; trims leading/trailing punctuation using standard algorithms that
    #     have shown themselves useful with Marc, using Marc21.trim_punctuation. **Instead**, use
    #    `extract_marc(whatever), trim_punctuation`
    #
    # * :default => String: if otherwise empty, add default value. **Instead**, use `extract_marc(whatever), default("default value")`
    #
    #
    # Examples:
    #
    #     to_field("title"), extract_marc("245abcd"), trim_punctuation
    #     to_field("id"),    extract_marc("001"), first_only
    #     to_field("geo"),   extract_marc("040a", :separator => nil), translation_map("marc040")
    #
    # If you'd like extract_marc functionality but you're not creating an indexer
    # step, see Traject::Macros::Marc21.extract_marc_from module method.
    def extract_marc(spec, options = {})

      # Raise an error if there are any invalid options, indicating a
      # misspelled or illegal option, using a string instead of a symbol, etc.

      unless (options.keys - EXTRACT_MARC_VALID_OPTIONS).empty?
        raise RuntimeError.new("Illegal/Unknown argument '#{(options.keys - EXTRACT_MARC_VALID_OPTIONS).join(', ')}' in extract_marc at #{Traject::Util.extract_caller_location(caller.first)}")
      end


      # We create the TranslationMap and the MarcExtractor here
      # on load, so the lambda can just refer to already created
      # ones, and not have to create a new one per-execution.
      #
      # Benchmarking shows for MarcExtractor at least, there is
      # significant performance advantage.

      if translation_map_arg  = options.delete(:translation_map)
        translation_map = Traject::TranslationMap.new(translation_map_arg)
      else
        translation_map = nil
      end


      extractor = Traject::MarcExtractor.new(spec, options)

      lambda do |record, accumulator, context|
        accumulator.concat extractor.extract(record)
        Marc21.apply_extraction_options(accumulator, options, translation_map)
      end
    end
    module_function :extract_marc

    # Convenience method when you want extract_marc behavior, but NOT
    # to create a lambda for an Indexer step, but instead just give
    # it a record directly and get back an array of values.
    #
    #     array = Traject::Indexer::Marc21.extract_marc_from(record, "245ab", :trim_punctuation => true)
    #
    # If you have a Traject::Indexer::Context and want to pass it in, you can:
    #
    #    array = Traject::Indexer::Marc21.extract_marc_from(record, "245ab", :trim_punctuation => true, :context => existing_context)
    def self.extract_marc_from(record, spec, options = {})
      output  = []
      # Nil context works, but if caller wants to pass one in
      # for better error reporting that's cool too.
      context = options.delete(:context) || nil

      extract_marc(spec, options).call(record, output, context)
      return output
    end

    # Side-effect the accumulator with the options
    def self.apply_extraction_options(accumulator, options, translation_map=nil)
      only_first              = options[:first]
      trim_punctuation        = options[:trim_punctuation]
      default_value           = options[:default]
      allow_duplicates        = options[:allow_duplicates]

      if only_first
        accumulator.replace Array(accumulator[0])
      end

      if translation_map
        translation_map.translate_array! accumulator
      end

      if trim_punctuation
        accumulator.collect! {|s| Marc21.trim_punctuation(s)}
      end

      unless allow_duplicates
        accumulator.uniq!
      end

      if options.has_key?(:default) && accumulator.empty?
        accumulator << default_value
      end
    end

    # A transformation macro version of trim_punctuation -- heuristics for trimming punctuation
    # from AACR2/MARC style values, to get bare values.
    def trim_punctuation
      lambda do |rec, accumulator|
        accumulator.collect! {|s| Marc21.trim_punctuation(s)}
      end
    end


    #  A list of symbols that are valid keys in the options hash
    EXTRACT_MARC_VALID_OPTIONS = [:first, :trim_punctuation, :default,
                                  :allow_duplicates, :separator, :translation_map,
                                  :alternate_script]

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
      unless (options.keys - SERIALZED_MARC_VALID_OPTIONS).empty?
        raise RuntimeError.new("Illegal/Unknown argument '#{(options.keys - SERIALZED_MARC_VALID_OPTIONS).join(', ')}' in seralized_marc at #{Traject::Util.extract_caller_location(caller.first)}")
      end

      format          = options[:format].to_s
      binary_escape   = (options[:binary_escape] != false)
      allow_oversized = (options[:allow_oversized] == true)

      raise ArgumentError.new("Need :format => [binary|xml|json] arg") unless %w{binary xml json}.include?(format)

      lambda do |record, accumulator, context|
        case format
        when "binary"
          binary = MARC::Writer.encode(record, allow_oversized)
          binary = Base64.encode64(binary) if binary_escape
          accumulator << binary
        when "xml"
          accumulator << MARC::FastXMLWriter.encode(record)
        when "json"
          accumulator << JSON.dump(record.to_hash)
        end
      end
    end
    SERIALZED_MARC_VALID_OPTIONS = [:format, :binary_escape, :allow_oversized]

    # Takes the whole record, by default from tags 100 to 899 inclusive,
    # all subfields, and adds them to output. Subfields in a record are all
    # joined by space by default.
    #
    # options
    # [:from] default '100', only tags >= lexicographically
    # [:to]   default '899', only tags <= lexicographically
    # [:separator] how to join subfields, default space, nil means don't join
    #
    # All fields in from-to must be marc DATA (not control fields), or weirdness
    #
    # Can always run this thing multiple times on the same field if you need
    # non-contiguous ranges of fields.
    def extract_all_marc_values(options = {})
      unless (options.keys - EXTRACT_ALL_MARC_VALID_OPTIONS).empty?
        raise RuntimeError.new("Illegal/Unknown argument '#{(options.keys - EXTRACT_ALL_MARC_VALID_OPTIONS).join(', ')}' in extract_all_marc at #{Traject::Util.extract_caller_location(caller.first)}")
      end
      options = {:from => "100", :to => "899", :separator => ' '}.merge(options)

      if [options[:from], options[:to]].map{|x| x.is_a? String}.any?{|x| x == false}
        raise ArgumentError.new("from/to options to extract_all_marc_values must be strings")
      end

      lambda do |record, accumulator, context|
        record.each do |field|
          next unless field.tag >= options[:from] && field.tag <= options[:to]
          subfield_values = field.subfields.collect {|sf| sf.value}
          next unless subfield_values.length > 0

          if options[:separator]
            accumulator << subfield_values.join( options[:separator])
          else
            accumulator.concat subfield_values
          end
        end
      end

    end
    EXTRACT_ALL_MARC_VALID_OPTIONS = [:separator, :from, :to]


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

      # If something went wrong and we got a nil, just return it
      return str unless str

      # trailing: comma, slash, semicolon, colon (possibly preceded and followed by whitespace)
      str = str.sub(/ *[ ,\/;:] *\Z/, '')

      # trailing period if it is preceded by at least three letters (possibly preceded and followed by whitespace)
      str = str.sub(/( *[[:word:]]{3,})\. *\Z/, '\1')

      # single square bracket characters if they are the start and/or end
      #   chars and there are no internal square brackets.
      str = str.sub(/\A\[?([^\[\]]+)\]?\Z/, '\1')

      # trim any leading or trailing whitespace
      str.strip!

      return str
    end

    def self.first!(arr)
      # kind of esoteric, but slice used this way does mutating first, yep
      arr.slice!(1, arr.length)
    end

  end
end
