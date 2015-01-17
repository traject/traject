require 'traject'

module Traject
  # Just some internal utility methods
  module Util

    def self.exception_to_log_message(e)
      indent = "    "

      msg  = indent + "Exception: " + e.class.name + ": " + e.message + "\n"
      msg += indent + e.backtrace.first + "\n"

      if (e.respond_to?(:getRootCause) && e.getRootCause && e != e.getRootCause )
        caused_by = e.getRootCause
        msg += indent + "Caused by\n"
        msg += indent + caused_by.class.name + ": " + caused_by.message + "\n"
        msg += indent + caused_by.backtrace.first + "\n"
      end

      return msg
    end

    # From ruby #caller method, you get an array. Pass one line
    # of the array here,  get just file and line number out.
    def self.extract_caller_location(str)
      str.split(':in `').first
    end



    # Ruby stdlib queue lacks a 'drain' function, we write one.
    #
    # Removes everything currently in the ruby stdlib queue, and returns
    # it an array.  Should be concurrent-safe, but queue may still have
    # some things in it after drain, if there are concurrent writers.
    def self.drain_queue(queue)
      result = []

      queue_size = queue.size
      begin
        queue_size.times do
          result << queue.deq(:raise_if_empty)
        end
      rescue ThreadError
        # Need do nothing, queue was concurrently popped, no biggie
      end

      return result
    end

  end
end
