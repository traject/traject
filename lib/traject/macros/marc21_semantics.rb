require 'traject/marc_extractor'

module Traject::Macros
  # extracting various semantic parts out of a Marc21 record. Few of these
  # come directly from Marc21 spec or other specs with no judgement, they
  # are all to some extent opinionated, based on actual practice and actual
  # data, some more than others. If it doens't do what you want, don't use it.
  # But if it does, you can use it, and continue to get updates with future
  # versions of Traject.
  module Marc21Semantics

    # Extract OCLC numbers from, by default 035a's, then strip known prefixes to get
    # just the num, and de-dup. 
    def oclcnum(extract_fields = "035a")
      lambda do |record, accumulator|
        list = Traject::MarcExtractor.extract_by_spec(record, extract_fields, :seperator => nil).collect! do |o|
          Marc21Semantics.oclcnum_trim(o)
        end.uniq!
        accumulator.concat list
      end
    end
    def self.oclcnum_trim(num)
      num.gsub(/\A(ocm)|(ocn)|(on)|(\(OCoLC\))/, '')
    end
  end
end