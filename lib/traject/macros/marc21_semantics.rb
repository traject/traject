require 'traject/marc_extractor'

module Traject::Macros
  # extracting various semantic parts out of a Marc21 record. Few of these
  # come directly from Marc21 spec or other specs with no judgement, they
  # are all to some extent opinionated, based on actual practice and actual
  # data, some more than others. If it doens't do what you want, don't use it.
  # But if it does, you can use it, and continue to get updates with future
  # versions of Traject.
  module Marc21Semantics
    # shortcut
    MarcExtractor = Traject::MarcExtractor

    # Extract OCLC numbers from, by default 035a's, then strip known prefixes to get
    # just the num, and de-dup.
    def oclcnum(extract_fields = "035a")
      lambda do |record, accumulator|
        list = MarcExtractor.extract_by_spec(record, extract_fields, :seperator => nil).collect! do |o|
          Marc21Semantics.oclcnum_trim(o)
        end

        accumulator.concat list.uniq if list
      end
    end
    def self.oclcnum_trim(num)
      num.gsub(/\A(ocm)|(ocn)|(on)|(\(OCoLC\))/, '')
    end


    # A sortable author value, created by concatenating:
    # * the main entry author, if there is one (fields 100, 110 or 111)
    # * the main entry uniform title (240), if there is one - not including non-filing chars as noted in 2nd indicator of the 240
    #   * If no 240, the 245 title, not including non-filing chars as noted in ind 2 of the 245
    #
    # Always returns a SINGLE string, based on concatenation.
    #
    # Thanks SolrMarc for basic logic.
    #
    # Note: You'll want to pay attention to the Solr schema field definition
    # you're using, and have it do case-insensitivity or any other normalization
    # you might want.
    #
    # these probably should be taking only certain subfields, but we're copying
    # from SolrMarc that didn't do so either and nobody noticed, so not bothering for now.
    def marc_sortable_author
      lambda do |record, accumulator|
        accumulator << Marc21Semantics.get_sortable_author(record)
      end
    end
    def self.get_sortable_author(record)
      onexx = MarcExtractor.extract_by_spec(record, "100:110:111", :first => true).first
      onexx = onexx.strip if onexx

      titles = []
      MarcExtractor.new(record, "240:245", :first => true).each_matching_line do |field, spec|
        non_filing = field.indicator2.to_i

        str = field.subfields.collect {|sf| sf.value}.join(" ")
        str = str.slice(non_filing, str.length)
        titles << str
      end.first
      title = titles.first
      title = title.strip if title

      return "#{onexx}#{title}"
    end


    # 245 a and b, with non-filing characters stripped off
    def marc_sortable_title
      lambda do |record, accumulator|
        accumulator << Marc21Semantics.get_sortable_title(record)
      end
    end
    def self.get_sortable_title(record)
      MarcExtractor.new(record, "245ab").collect_matching_lines do |field, spec, extractor|
        str = extractor.collect_subfields(field, spec).first

        non_filing = field.indicator2.to_i
        str = str.slice(non_filing, str.length)
        str = Marc21.trim_punctuation(str)

        str
      end.first
    end

    # maps languages, by default out of 008[35-37] and 041a and 041d
    #
    # Can specify other spec if you want, say, 041b (lang of abstract)
    # or 041e (lang of librettos), or 041h (lang of original) instead or in addition.
    #
    # de-dups values so you don't get the same one twice.
    #
    # Exact spec of #marc_languages may change with new user data on what
    # works best.
    def marc_languages(spec = "008[35-37]:041a:041d")
      translation_map = Traject::TranslationMap.new("marc_languages")

      lambda do |record, accumulator|
        codes = MarcExtractor.new(record, spec, :seperator => "nil").collect_matching_lines do |field, spec, extractor|
          if extractor.control_field?(field)
            (spec[:bytes] ? field.value.byteslice(spec[:bytes]) : field.value)
          else
            extractor.collect_subfields(field, spec).collect do |value|
              # sometimes multiple language codes are jammed together in one subfield, and
              # we need to seperate ourselves. sigh.
              unless value.length == 3
                value = value.scan(/.{1,3}/) # split into an array of 3-length substrs
              end
              value
            end.flatten
          end
        end
        codes = codes.uniq

        translation_map.translate_array!(codes)

        accumulator.concat codes
      end
    end

    # Adds in marc fields in spec (default is recommended series spec, but you can specify your own)
    # -- only trick is that 490's are skipped of first indicator is 1 -- if 490 first
    # indicator is "1", "series traced", that means the series title mentioned here is
    # already covered by another field we're including, so we don't want to double count it, possibly
    # with slight variation.
    def marc_series_facet(spec = "440a:490a:800abcdt:810abcdt:811acdeft:830adfgklmnoprst")
      lambda do |record, accumulator|
        MarcExtractor.new(record, spec).collect_matching_lines do |field, spec, extractor|
          extractor.collect_subfields(field, spec) unless (field.tag == "490" && field.indicator1 == "1")
        end
      end
    end


    # Takes marc 048ab instrument code, and translates it to human-displayable
    # string. Takes first two chars of 048a or b, to translate (ignores numeric code)
    #
    # Pass in custom spec if you want just a or b, to seperate soloists or whatever.
    def marc_instrumentation_humanized(spec = "048ab", options = {})
      translation_map = Traject::TranslationMap.new(options[:translation_map] || "marc_instruments")

      lambda do |record, accumulator|
        values = Traject::MarcExtractor.extract_by_spec(record, spec, :seperator => nil)
        human = values.collect do |value|
          translation_map[ value.slice(0, 2) ]
        end.uniq
        accumulator.concat human if human && human.length > 0
      end
    end

    # This weird one actually returns marc instrumentation codes, not
    # humanized. But it normalizes them by breaking them down into a numeric and non-numeric
    # version. For instance "ba01" will be indexed as both "ba01" and "ba".
    # ALSO, if the code is in a subfield b (soloist), it'll be indexed
    # _additionally_ as "ba01.s" and "ba.s".
    #
    # This has proven useful for expert music librarian searching.
    #def marc_instrument_code_normalized
    #  MarcExtractor.new(record, "048").collect_matching_lines do |field, spec, extractor|

    #  end
    #end

  end
end