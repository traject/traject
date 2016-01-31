# An indexing step definition, including it's source location
# for logging
#
# This one represents an "each_record" step, a subclass below
# for "to_field"
#
# source_location is just a string with filename and line number for
# showing to devs in debugging.

class Traject::Indexer
  class EachRecordStep
    attr_accessor :source_location, :block
    attr_reader :lambda

    def initialize(lambda, block, source_location)
      self.lambda          = lambda
      self.block           = block
      self.source_location = source_location

      self.validate!
    end

    # Set the arity of the lambda expression just once, when we define it
    def lambda=(lam)
      @lambda = lam
      @lambda_arity = @lambda ?  @lambda.arity : 0
    end

    # raises if bad data
    def validate!
      unless self.lambda or self.block
        raise ArgumentError.new("Missing Argument: each_record must take a block/lambda as an argument (#{self.inspect})")
      end

      [self.lambda, self.block].each do |proc|
        # allow negative arity, meaning variable/optional, trust em on that.
        # but for positive arrity, we need 1 or 2 args
        if proc
          unless proc.is_a?(Proc)
            raise NamingError.new("argument to each_record must be a block/lambda, not a #{proc.class} #{self.inspect}")
          end
          if (proc.arity == 0 || proc.arity > 2)
            raise ArityError.new("block/proc given to each_record needs 1 or 2 arguments: #{self.inspect}")
          end
        end
      end
    end

    # For each_record, always return an empty array as the
    # accumulator, since it doesn't have those kinds of side effects

    def execute(context)
      sr = context.source_record

      if @block
        @block.call(sr, context)
      end

      if @lambda
        if @lambda_arity == 1
          @lambda.call(sr)
        else
          @lambda.call(sr, context)
        end

      end
      return [] # empty -- no accumulator for each_record
    end

    # Over-ride inspect for outputting error messages etc.
    def inspect
      "(each_record at #{source_location})"
    end
  end


# An indexing step definition for a "to_field" step to specific
# field.
  class ToFieldStep
    attr_accessor :field_name, :block, :source_location
    attr_reader :lambda

    def initialize(fieldname, lambda, block, source_location)
      self.field_name      = fieldname
      self.lambda          = lambda
      self.block           = block
      self.source_location = source_location

      validate!
    end

    def lambda=(lam)
      @lambda = lam
      @lambda_arity = @lambda ?  @lambda.arity : 0
    end

    def validate!

      if self.field_name.nil? || !self.field_name.is_a?(String) || self.field_name.empty?
        raise NamingError.new("to_field requires the field name (as a string) as the first argument at #{self.source_location})")
      end

      [self.lambda, self.block].each do |proc|
        # allow negative arity, meaning variable/optional, trust em on that.
        # but for positive arrity, we need 2 or 3 args
        if proc && (proc.arity == 0 || proc.arity == 1 || proc.arity > 3)
          raise ArityError.new("error parsing field '#{self.field_name}': block/proc given to to_field needs 2 or 3 (or variable) arguments: #{proc} (#{self.inspect})")
        end
      end
    end

    # Override inspect for developer debug messages
    def inspect
      "(to_field #{self.field_name} at #{self.source_location})"
    end

    def execute(context)
      accumulator = []
      sr = context.source_record

      if @block
        @block.call(sr, accumulator, context)
      end

      if @lambda
        if @lambda_arity == 2
          @lambda.call(sr, accumulator)
        else
          @lambda.call(sr, accumulator, context)
        end
      end

      return accumulator
    end

  end

# A class representing a block of logic called after
# processing, registered with #after_processing
  class AfterProcessingStep
    attr_accessor :lambda, :block, :source_location

    def initialize(lambda, block, source_location)
      self.lambda          = lambda
      self.block           = block
      self.source_location = source_location
    end

    # after_processing steps get no args yielded to
    # their blocks, they just are what they are.
    def execute
      @block.call if @block
      @lambda.call if @lambda
    end

    def inspect
      "(after_processing at #{self.source_location}"
    end
  end
end
