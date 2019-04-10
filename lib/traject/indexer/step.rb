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

    EMPTY_ACCUMULATOR = [].freeze

    def initialize(lambda, block, source_location)
      self.lambda          = lambda
      self.block           = block
      self.source_location = source_location

      self.validate!
    end

    def to_field_step?
      false
    end


    # Set the arity of the lambda expression just once, when we define it
    def lambda=(lam)
      @lambda_arity = 0 # assume
      @lambda = lam

      return unless lam

      if @lambda.is_a?(Proc)
        @lambda_arity = @lambda.arity
      else
        raise NamingError.new("argument to each_record must be a block/lambda, not a #{lam.class} #{self.inspect}")
      end
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

      if @lambda
        if @lambda_arity == 1
          @lambda.call(sr)
        else
          @lambda.call(sr, context)
        end
      end

      if @block
        @block.call(sr, context)
      end

      return EMPTY_ACCUMULATOR # empty -- no accumulator for each_record
    end

    # Over-ride inspect for outputting error messages etc.
    def inspect
      "(each_record at #{source_location})"
    end
  end


  # An indexing step definition for a "to_field" step to specific
  # field. The first field name argument can be an array of multiple field
  # names, the processed values will be added to each one.
  class ToFieldStep
    attr_reader :field_name, :block, :source_location, :procs

    def initialize(field_name, procs, block, source_location)
      @field_name      = field_name.freeze
      @procs           = procs.freeze
      @block           = block.freeze
      @source_location = source_location.freeze

      validate!
    end

    def to_field_step?
      true
    end

    def validate!

      unless (field_name.is_a?(String) && ! field_name.empty?) || (field_name.is_a?(Array) && field_name.all? { |f| f.is_a?(String) && ! f.empty? })
        raise NamingError.new("to_field requires the field name (as a string), or an array of such, as the first argument at #{self.source_location})")
      end

      [*self.procs, self.block].each do |proc|
        # allow negative arity, meaning variable/optional, trust em on that.
        # but for positive arrity, we need 2 or 3 args
        if proc && (proc.arity == 0 || proc.arity == 1 || proc.arity > 3)
          raise ArityError.new("error parsing field '#{self.field_name}': block/proc given to to_field needs 2 or 3 (or variable) arguments: #{proc} (#{self.inspect})")
        end
      end
    end

    # Override inspect for developer debug messages
    def inspect
      "(to_field #{self.field_name.inspect} at #{self.source_location})"
    end

    def execute(context)
      accumulator = []
      source_record = context.source_record

      [*self.procs, self.block].each do |aProc|
        next unless aProc
        if aProc.arity == 2
          aProc.call(source_record, accumulator)
        else
          aProc.call(source_record, accumulator, context)
        end
      end

      add_accumulator_to_context!(accumulator, context)
      return accumulator
    end


    # These constqnts here for historical/legacy reasons, they really oughta
    # live in Traject::Context, but in case anyone is referring to them
    # we'll leave them here for now.
    ALLOW_NIL_VALUES       = "allow_nil_values".freeze
    ALLOW_EMPTY_FIELDS     = "allow_empty_fields".freeze
    ALLOW_DUPLICATE_VALUES = "allow_duplicate_values".freeze

    # Add the accumulator to the context with the correct field name(s).
    # Do post-processing on the accumulator (remove nil values, allow empty
    # fields, etc)
    def add_accumulator_to_context!(accumulator, context)
      # field_name can actually be an array of field names
      context.add_output(field_name, *accumulator)
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


    def to_field_step?
      false
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
