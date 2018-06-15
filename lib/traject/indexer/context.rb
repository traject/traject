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
    # 1-based position in stream of processed records.
    attr_accessor :position

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
      source_id = source_record_id_proc && source_record_id_proc.call(source_record)
      output_id = self.output_hash["id"]

      return [source_id, output_id].compact.join("/")
    end

  end


end

