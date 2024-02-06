# Encoding: UTF-8

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

    # Extract OCLC numbers from, by default 035a's by known prefixes, then stripped
    # just the num, and de-dup.
    def oclcnum(extract_fields = "035a")
      extractor = MarcExtractor.new(extract_fields, :separator => nil)

      lambda do |record, accumulator|
        list = extractor.extract(record).collect! do |o|
          Marc21Semantics.oclcnum_extract(o)
        end.compact

        accumulator.concat list.uniq if list
      end
    end

    # If a num begins with a known OCLC prefix, return it without the prefix.
    # otherwise nil.
    #
    # Allow (OCoLC) and/or ocn/ocm/on

    OCLCPAT = /
      \A\s*
      (?:(?:\(OCoLC\)) |
         (?:\(OCoLC\))?(?:(?:ocm)|(?:ocn)|(?:on))
         )(\d+)
         /x

    def self.oclcnum_extract(num)
      if m = OCLCPAT.match(num)
        return m[1]
      else
        return nil
      end
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
      onexx = MarcExtractor.cached("100:110:111", :first => true, :trim_punctuation => true).extract(record).first
      onexx = onexx.strip if onexx

      titles = []
      MarcExtractor.cached("240:245", :first => true).each_matching_line(record) do |field, spec|
        non_filing = field.indicator2.to_i

        str = field.subfields.collect {|sf| Marc21.trim_punctuation(sf.value.strip).strip}.join(" ")
        str = str.slice(non_filing, str.length)
        titles << str
      end.first
      title = titles.first
      title = title.strip if title

      return [onexx, title].compact.join("   ")
    end


    # 245 a and b, with non-filing characters stripped off
    def marc_sortable_title
      lambda do |record, accumulator|
        st = Marc21Semantics.get_sortable_title(record)
        accumulator << st if st
      end
    end

    def self.get_sortable_title(record)
      MarcExtractor.cached("245ab").collect_matching_lines(record) do |field, spec, extractor|
        str = extractor.collect_subfields(field, spec).first

        if str.nil?
          # maybe an APPM archival record with only a 'k'
          str = field['k']
        end
        if str.nil?
          # still? All we can do is bail, I guess
          return nil
        end

        non_filing = field.indicator2.to_i
        str = str.slice(non_filing, str.length)
        str = Marc21.trim_punctuation(str)

        str
      end.first
    end



    # A generic way to strip a filing version (i.e., a string with the non-filing
    # characters stripped off)
    #
    # Always returns an array. If :include_original=>true is passed in,
    # that array will include the original string with the non-filing
    # characters still in it.

    def extract_marc_filing_version(spec='245abdefghknp', opts={})
      include_original = opts.delete(:include_original)
      if opts.size > 0
        raise RuntimeError.new("extract_marc_filing_version can take only :include_original as an argument, not #{opts.keys.map{|x| "'#{x}'"}.join(' or ')}")
      end

      extractor = Traject::MarcExtractor.cached(spec, opts)

      lambda do |record, accumulator, context|
        extractor.collect_matching_lines(record) do |field, spec|
          str = extractor.collect_subfields(field, spec).first
          next unless str and !str.empty?
          vals = [Marc21Semantics.filing_version(field, str, spec)]
          if include_original
            vals.unshift str
            vals.uniq!
          end
          accumulator.concat vals
        end
      end
    end




    # Take in a field, a string extracted from that field, and a spec and
    # return the filing version (i.e., the string without the
    # non-filing characters)

    def self.filing_version(field, str, spec)
      # Control fields don't have non-filing characters
      return str if field.kind_of? MARC::ControlField

      # 2nd indicator must be > 0
      ind2 = field.indicator2.to_i
      return str unless ind2 > 0

      # The spechash must either (a) have no subfields specified, or
      # (b) include the first subfield in the record

      subs = spec.subfields

      # Get the code for the first alphabetic subfield, which would be
      # the one getting characters shifted off

      first_alpha_code = field.subfields.first{|sf| sf.code =~ /[a-z]/}.code

      return str unless subs && subs.include?(first_alpha_code)

      # OK. If we got this far we actually need to strip characters off the string

      return str[ind2..-1]
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

      extractor = MarcExtractor.new(spec, :separator => nil)

      lambda do |record, accumulator|
        codes = extractor.collect_matching_lines(record) do |field, spec, extractor|
          if extractor.control_field?(field)
            (spec.bytes ? field.value.byteslice(spec.bytes) : field.value)
          else
            extractor.collect_subfields(field, spec).collect do |value|
              # sometimes multiple language codes are jammed together in one subfield, and
              # we need to separate ourselves. sigh.
              unless value.length == 3
                # split into an array of 3-length substrs; JRuby has problems with regexes
                # across threads, which is why we don't use String#scan here.
                value = value.chars.each_slice(3).map(&:join)
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
      extractor = MarcExtractor.new(spec)

      lambda do |record, accumulator|
        values = extractor.collect_matching_lines(record) do |field, spec, extractor|
          extractor.collect_subfields(field, spec) unless (field.tag == "490" && field.indicator1 == "1")
        end.compact

        # trim punctuation
        values.collect! do |s|
          Marc21.trim_punctuation(s)
        end

        accumulator.concat( values )
      end
    end


    # Takes marc 048ab instrument code, and translates it to human-displayable
    # string. Takes first two chars of 048a or b, to translate (ignores numeric code)
    #
    # Pass in custom spec if you want just a or b, to separate soloists or whatever.
    def marc_instrumentation_humanized(spec = "048ab", options = {})
      translation_map = Traject::TranslationMap.new(options[:translation_map] || "marc_instruments")

      extractor = MarcExtractor.new(spec, :separator => nil)

      lambda do |record, accumulator|
        values = extractor.extract(record)
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
    # This has proven useful for expert music librarian searching by hand; it could
    # also be the basis of a GUI that executes searches behind the scenes for these
    # codes.
    def marc_instrument_codes_normalized(spec = "048")
      soloist_suffix = ".s"

      extractor = MarcExtractor.new("048", :separator => nil)

      return lambda do |record, accumulator|
        accumulator.concat(
          extractor.collect_matching_lines(record) do |field, spec, extractor|
            values = []

            field.subfields.each do |sf|
              v = sf.value
              # Unless there's at least two chars, it's malformed, we can
              # do nothing
              next unless v.length >= 2

              # Index both with and without number -- both with soloist suffix
              # if in a $b
              values << v
              values << "#{v}#{soloist_suffix}" if sf.code == 'b'
              if v.length >= 4
                bare = v.slice(0,2) # just the prefix
                values << bare
                values << "#{bare}#{soloist_suffix}" if sf.code == 'b'
              end
            end
            values
          end.uniq
        )
      end
    end

    # An opinionated algorithm for getting a SINGLE publication date out of marc
    #
    # * Prefers using 008, but will resort to 260c
    # * If 008 represents a date range, will take the midpoint of the range,
    #     only if range is smaller than estimate_tolerance, default 15 years.
    # * Ignores dates below min_year (default 500) or above max_year (this year plus 6 years),
    #     because experience shows too many of these were in error.
    #
    # Yeah, this code ends up ridiculous.
    def marc_publication_date(options = {})
      estimate_tolerance  = options[:estimate_tolerance] || 15
      min_year            = options[:min_year] || 500
      max_year            = options[:max_year] || (Time.new.year + 6)

      lambda do |record, accumulator|
        date = Marc21Semantics.publication_date(record, estimate_tolerance, min_year, max_year)
        accumulator << date if date
      end
    end

    # See #marc_publication_date. Yeah, this is a holy mess.
    # Maybe it should actually be extracted to it's own class!
    def self.publication_date(record, estimate_tolerance = 15, min_year = 500, max_year = (Time.new.year + 6))
      field008 = MarcExtractor.cached("008").extract(record).first
      found_date = nil

      if field008 && field008.length >= 11
        date_type = field008.slice(6)
        date1_str = field008.slice(7,4)
        if field008.length > 15
          date2_str = field008.slice(11, 4)
        else
          date2_str = date1_str
        end

        # for date_type q=questionable, we expect to have a range.
        if date_type == 'q' and date1_str != date2_str
          # make unknown digits at the beginning or end of range,
          date1 = date1_str.sub("u", "0").to_i
          date2 = date2_str.sub("u", "9").to_i
          # do we have a range we can use?
          if (date2 > date1) && ((date2 - date1) <= estimate_tolerance)
            found_date = (date2 + date1)/2
          end
        end
        # didn't find a date that way, and anything OTHER than date_type
        # n=unknown, q=questionable, try single date -- for some date types,
        # there's a date range between date1 and date2, yeah, we often take
        # the FIRST date then, the earliest. That's just what we're doing.
        if found_date.nil? && date_type != 'n' && date_type != 'q'
          # in date_type 'r', second date is original publication date, use that I think?
          date_str = ((date_type == 'r' || date_type == 'p') && date2_str.to_i != 0) ? date2_str : date1_str
          # Deal with stupid 'u's, which end up meaning a range too,
          # find midpoint and make sure our tolerance is okay.
          ucount = 0
          while (!date_str.nil?) && (i = date_str.index('u'))
            ucount += 1
            date_str[i] = "0"
          end
          date = date_str.to_i
          if ucount > 0 && date != 0
            delta = 10 ** ucount # 10^ucount, expontent
            if delta <= estimate_tolerance
              found_date = date + (delta/2)
            end
          elsif date != 0
            found_date = date
          end
        end
      end
      # Okay, nothing from 008, first try 264, then try 260
      if found_date.nil?
        v264c = MarcExtractor.cached("264c", :separator => nil).extract(record).first
        v260c = MarcExtractor.cached("260c", :separator => nil).extract(record).first
        # just try to take the first four digits out of there, we're not going to try
        # anything crazy.
        if m = /(\d{4})/.match(v264c)
          found_date = m[1].to_i
        elsif m = /(\d{4})/.match(v260c)
            found_date = m[1].to_i
        end
      end

      # is it within our acceptable range?
      found_date = nil if found_date && (found_date < min_year || found_date > max_year)

      return found_date
    end

    # REGEX meant to rule out obvious non-LCC's, and only allow things
    # plausibly LCC's.
    LCC_REGEX = /\A *[A-Z]{1,3}[ .]*(?:(\d+)(?:\s*?\.\s*?(\d+))?).*/
    # Looks up Library of Congress Classification (LCC) or NLM Medical Subject Headings (MeSH)
    # from usual parts of the marc record. Maps them to high-level broad categories,
    # basically just using the first part of the LCC. Note it's just looking in bib-level
    # locations for LCCs, you're on your own with holdings.
    #
    # Sanity checks to make sure the thing looks like an LCC with a regex, before
    # mapping.
    #
    # Will call it 'Unknown' if it's got nothing else, or pass in :default => something else,
    # or nil.
    #
    # The categories output aren't great, but they're something.
    def marc_lcc_to_broad_category( options = {}, spec="050a:060a:090a:096a")
      # Trying to match things that look like LCC, and not match things
      # that don't. Is tricky.
      lcc_regex = LCC_REGEX
      default_value = options.has_key?(:default) ? options[:default] : "Unknown"
      translation_map = Traject::TranslationMap.new("lcc_top_level")

      extractor = MarcExtractor.new(spec, :separator => nil)

      lambda do |record, accumulator|
        candidates = extractor.extract(record)

        candidates.reject! do |candidate|
          !(lcc_regex.match candidate)
        end

        accumulator.concat translation_map.translate_array!(candidates.collect {|a| a.lstrip.slice(0, 1)}).uniq

        if default_value && accumulator.empty?
          accumulator << default_value
        end
      end
    end

    # An opinionated method of making a geographic facet out of BOTH 048 marc
    # codes, AND geo subdivisions in 6xx LCSH subjects.
    #
    # The LCSH geo subdivisions are further normalized:
    # * geo qualifiers in $z fields into parens, so "Germany -- Berlin" becomes "Berlin (Germany)"
    #   (to be consistent with how same areas are written in $a fields -- doesn't
    #    get everything, but gets lots of em)
    # * qualified regions like that are additionally 'posted up', so "Germany -- Berlin" gets
    #   recorded additionally as "Germany"
    def marc_geo_facet(options = {})
      marc_geo_map = Traject::TranslationMap.new("marc_geographic")

      a_fields_spec = options[:geo_a_fields] || "651a:691a"
      z_fields_spec = options[:geo_z_fields] || "600:610:611:630:648:650:654:655:656:690:651:691"

      extractor_043a      = MarcExtractor.new("043a", :separator => nil)
      extractor_a_fields  = MarcExtractor.new(a_fields_spec, :separator => nil)
      extractor_z_fields  = MarcExtractor.new(z_fields_spec)

      lambda do |record, accumulator|

        accumulator.concat(
          extractor_043a.extract(record).collect do |code|
            # remove any trailing hyphens, then map
            marc_geo_map[code.gsub(/\-+\Z/, '')]
          end.compact
        )

        #LCSH 651a and 691a go in more or less normally.
        accumulator.concat(
          extractor_a_fields.extract(record).collect do |s|
            # remove trailing periods, which they sometimes have if they were
            # at end of LCSH.
            s.sub(/\. */, '')
          end
        )

        # fields we take z's from have a bit more normalization
        extractor_z_fields.each_matching_line(record) do |field, spec, extractor|
          z_fields = field.subfields.find_all {|sf| sf.code == "z"}.collect {|sf| sf.value }
          # depending on position in total field, may be a period on the end
          # we want to remove.
          z_fields.collect! {|s| s.gsub(/\. *\Z/, '')}

          if z_fields.length == 2
            # normalize subdivision as parenthetical
            accumulator << "#{z_fields[1]} (#{z_fields[0]})"
            # and 'post up'
            accumulator << z_fields[0]
          else
            # just add all the z's if there's 1 or more than 2.
            accumulator.concat z_fields
          end
        end
        accumulator.uniq!
      end
    end

    # Opinionated routine to create values for a chronology/era facet out of
    # LCSH chron subdivisions. Does some normalization:
    # for 651 with a chron facet fitting the form
    # "aaaaa, yyyy-yyyy", it will add in the $a. For instance:
    # 651   a| United States x| History y| Civil War, 1861-1865
    # --> "United States: Civil War, 1861-1865"
    def marc_era_facet
      ordinary_fields_spec = "600y:610y:611y:630y:648ay:650y:654y:656y:690y"
      special_fields_spec = "651:691"
      separator = ": "

      extractor_ordinary_fields = MarcExtractor.new(ordinary_fields_spec)
      extractor_special_fields  = MarcExtractor.new(special_fields_spec)

      lambda do |record, accumulator|
        # straightforward ones


        accumulator.concat( extractor_ordinary_fields.extract(record).collect do |v|
          # May have a period we have to remove, if it was at end of tag
          v.sub(/\. *\Z/, '')
        end)

        # weird ones
        special_fields_regex = /\A\s*.+,\s+(ca.\s+)?\d\d\d\d?(-\d\d\d\d?)?( B\.C\.)?[.,; ]*\Z/
        extractor_special_fields.each_matching_line(record) do |field, spec, extractor|
          field.subfields.each do |sf|
            next unless sf.code == 'y'
            if special_fields_regex.match(sf.value)
              # it's our pattern, add the $a in please
              accumulator << "#{field['a']}#{separator}#{sf.value.sub(/\. *\Z/, '')}"
            else
              accumulator << sf.value.sub(/\. *\Z/, '')
            end
          end
        end
        accumulator.uniq!
      end
    end

    # Extracts LCSH-carrying fields, and formatting them
    # as a pre-coordinated LCSH string, for instance suitable for including
    # in a facet.
    #
    # You can supply your own list of fields as a spec, but for significant
    # customization you probably just want to write your own method in
    # terms of the Marc21Semantics.assemble_lcsh method.
    def marc_lcsh_formatted(options = {})
      spec            = options[:spec] || "600:610:611:630:648:650:651:654:662"
      subd_separator  = options[:subdivison_separator] || " — "
      other_separator = options[:other_separator] || " "

      extractor       = MarcExtractor.new(spec)

      return lambda do |record, accumulator|
        accumulator.concat( extractor.collect_matching_lines(record) do |field, spec|
          Marc21Semantics.assemble_lcsh(field, subd_separator, other_separator)
        end)
      end

    end

    # Takes a MARC::Field and formats it into a pre-coordinated LCSH string
    # with subdivision seperators in the right place.
    #
    # For 600 fields especially, need to not just join with subdivision seperator
    # to take acount of $a$d$t -- for other fields, might be able to just
    # join subfields, not sure.
    #
    # WILL strip trailing period from generated string, contrary to some LCSH practice.
    # Our data is inconsistent on whether it has period or not, this was
    # the easiest way to standardize.
    #
    # Default subdivision seperator is em-dash with spaces, set to '--' if you want.
    #
    # Cite: "Dash (-) that precedes a subdivision in an extended 600 subject heading
    # is not carried in the MARC record. It may be system generated as a display constant
    # associated with the content of subfield $v, $x, $y, and $z."
    # http://www.loc.gov/marc/bibliographic/bd600.html
    def self.assemble_lcsh(marc_field, subd_separator = " — ", other_separator = " ")
      str = ""
      subd_prefix_codes = %w{v x y z}


      marc_field.subfields.each_with_index do |sf, i|
        # ignore non-alphabetic, like numeric control subfields
        next unless /\A[a-z]\Z/.match(sf.code)

        prefix = if subd_prefix_codes.include? sf.code
          subd_separator
        elsif i == 0
          ""
        else
          other_separator
        end
        str << prefix << sf.value
      end

      str.gsub!(/\.\Z/, '')

      return nil if str == ""

      return str
    end


  end
end
