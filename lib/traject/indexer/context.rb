# Represents the context of a specific record being indexed, passed
# to indexing logic blocks
#
# Arg source_record_id_proc is a lambda that takes one arg (indexer-specific source record),
# and returns an ID for it suitable for use in log messages.
class Traject::Indexer
  class Context
    def initialize(hash_init = {})
      # TODO, argument checking for required args?

      self.clipboard   = {}
      self.output_hash = {}

      hash_init.each_pair do |key, value|
        self.send("#{key}=", value)
      end

      @skip = false
    end

    attr_accessor :clipboard, :output_hash, :logger
    attr_accessor :index_step, :source_record, :settings, :source_record_id_proc
    # 'position' is a 1-based position in stream of processed records.
    attr_accessor :position
    # sometimes we have multiple inputs, input_name describes the current one, and
    # position_in_input the position of the record in the current input -- both can
    # sometimes be blanl when we don't know.
    attr_accessor :input_name, :position_in_input

    # Should we be skipping this record?
    attr_accessor :skipmessage

    # Set the fact that this record should be skipped, with an
    # optional message
    def skip!(msg = '(no message given)')
      @skipmessage = msg
      @skip        = true
    end

    # Should we skip this record?
    def skip?
      @skip
    end

    # Useful for describing a record in a log or especially
    # error message. May be useful to combine with #position
    # in output messages, especially since this method may sometimes
    # return empty string if info on record id is not available.
    #
    # Returns id from source_record (if we can get it from a source_record_id_proc),
    # then a slash,then output_hash["id"] -- if both
    # are present. Otherwise may return just one, or even an empty string.
    def source_record_id
      source_record_id_proc && source_record_id_proc.call(source_record)
    end

    # a string label that can be used to refer to a particular record in log messages and
    # exceptions. Includes various parts depending on what we got.
    def record_inspect
      str = "<"

      str << "record ##{position}" if position

      if input_name && position_in_input
        str << " (#{input_name} ##{position_in_input}), "
      elsif position
        str << ", "
      end

      if source_id = source_record_id
        str << "source_id:#{source_id} "
      end

      if output_id = self.output_hash["id"]
        str << "output_id:#{[output_id].join(',')}"
      end

      str.chomp!(" ")
      str.chomp!(",")
      str << ">"

      str
    end

    # Add values to an array in context.output_hash with the specified key/field_name(s).
    # Creates array in output_hash if currently nil.
    #
    # Post-processing/filtering:
    #
    # * uniqs accumulator, unless settings["allow_dupicate_values"] is set.
    # * Removes nil values unless settings["allow_nil_values"] is set.
    # * Will not add an empty array to output_hash (will leave it nil instead)
    #   unless settings["allow_empty_fields"] is set.
    #
    # Multiple values can be added with multiple arguments (we avoid an array argument meaning
    # multiple values to accomodate odd use cases where array itself is desired in output_hash value)
    #
    # @param field_name [String,Symbol,Array<String>,Array[<Symbol>]] A key to set in output_hash, or
    #   an array of such keys.
    #
    # @example add one value
    #   context.add_output(:additional_title, "a title")
    #
    # @example add multiple values as multiple params
    #   context.add_output("additional_title", "a title", "another title")
    #
    # @example add multiple values as multiple params from array using ruby spread operator
    #   context.add_output(:some_key, *array_of_values)
    #
    # @example add to multiple keys in output hash
    #   context.add_output(["key1", "key2"], "value")
    #
    # @return [Traject::Context] self
    #
    # Note for historical reasons relevant settings key *names* are in constants in Traject::Indexer::ToFieldStep,
    # but the settings don't just apply to ToFieldSteps
    def add_output(field_name, *values)
      values.compact! unless self.settings && self.settings[Traject::Indexer::ToFieldStep::ALLOW_NIL_VALUES]

      return self if values.empty? and not (self.settings && self.settings[Traject::Indexer::ToFieldStep::ALLOW_EMPTY_FIELDS])

      Array(field_name).each do |key|
        accumulator = (self.output_hash[key.to_s] ||= [])
        accumulator.concat values
        accumulator.uniq! unless self.settings && self.settings[Traject::Indexer::ToFieldStep::ALLOW_DUPLICATE_VALUES]
      end

      return self
    end
  end


end

