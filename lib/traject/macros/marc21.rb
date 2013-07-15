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

    

  end
end