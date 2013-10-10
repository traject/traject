module Traject::Macros
  module Basic
    def literal(literal)
      lambda do |record, accumulator, context|
        accumulator << literal
      end
    end
  end
end
