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
        end.uniq!
        accumulator.concat list
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
    def sortable_author
      lambda do |record, accumulator|
        accumulator << Marc21Semantics.get_sortable_author(record)
      end
    end
    def self.get_sortable_author(record)
      onexx = MarcExtractor.extract_by_spec(record, "100:110:111", :first => true).first
      onexx = onexx.strip if onexx

      titles = []
      MarcExtractor.new(record, MarcExtractor.parse_string_spec("240:245"), :first => true).each_matching_line do |field, spec|
        non_filing = field.indicator2.to_i

        str = field.subfields.collect {|sf| sf.value}.join(" ")
        str = str.slice(non_filing, str.length)
        titles << str
      end.first
      title = titles.first
      title = title.strip if title

      return "#{onexx}#{title}"
    end
  end
end