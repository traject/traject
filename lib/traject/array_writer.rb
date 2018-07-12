module Traject
  # Uses #put method from the traject writer API to just accumulate
  # output_hash'es in an array. Useful for testing, or for simple programmatic
  # use.
  #
  # Useful with process_with:
  #
  #     indexer.process_with(source_array, ArrayWriter.new).values
  #       # => array of output_hash's
  #
  # Recommend against using it with huge number of records, as it will
  # of course store them all in memory.
  #
  # Uses Concurrent::Arrays internally, so should be safe for use as writer
  # in concurrency scenarios.
  class ArrayWriter
    attr_reader :values, :contexts

    def initialize(_settings = nil)
      @values = Concurrent::Array.new
      @contexts = Concurrent::Array.new
    end

    def put(context)
      contexts << context
      values << context.output_hash
    end

    def clear!
      @contexts.delete
      @values.delete
    end
  end
end
