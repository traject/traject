module Traject
  # Just some internal utility methods
  module Util

    def self.exception_to_log_message(e)
      indent = "    "

      msg = indent + "Exception: " + e.class.name + ": " + e.message + "\n"
      msg += indent + e.backtrace.first + "\n"

      if (e.respond_to?(:getRootCause) && e.getRootCause && e != e.getRootCause)
        caused_by = e.getRootCause
        msg       += indent + "Caused by\n"
        msg       += indent + caused_by.class.name + ": " + caused_by.message + "\n"
        msg       += indent + caused_by.backtrace.first + "\n"
      end

      return msg
    end

    # From ruby #caller method, you get an array. Pass one line
    # of the array here,  get just file and line number out.
    def self.extract_caller_location(str)
      str.split(':in `').first
    end

    # Provide a config source file path, and an exception.
    #
    # Returns the line number from the first line in the stack
    # trace of the exception that matches your file path.
    # of the first line in the backtrace matching that file_path.
    #
    # Returns `nil` if no suitable backtrace line can be found.
    #
    # Has special logic to try and grep the info out of a SyntaxError, bah.
    def self.backtrace_lineno_for_config(file_path, exception)
      # For a SyntaxError, we really need to grep it from the
      # exception message, it really appears to be nowhere else. Ugh.
      if exception.kind_of? SyntaxError
        if m = /:(\d+):/.match(exception.message)
          return m[1].to_i
        end
      end

      # Otherwise we try to fish it out of the backtrace, first
      # line matching the config file path.

      # exception.backtrace_locations exists in MRI 2.1+, which makes
      # our task a lot easier. But not yet in JRuby 1.7.x, so we got to
      # handle the old way of having to parse the strings in backtrace too.
      if (exception.respond_to?(:backtrace_locations) &&
          exception.backtrace_locations &&
          exception.backtrace_locations.length > 0)
        location = exception.backtrace_locations.find do |bt|
          bt.path == file_path
        end
        return location ? location.lineno : nil
      else # have to parse string backtrace
        exception.backtrace.each do |line|
          if line.start_with?(file_path)
            if m = /\A.*\:(\d+)\:in/.match(line)
              ch(line)
              return m[1].to_i
              break
            end
          end
        end
        # if we got here, we have nothing
        return nil
      end
    end

    # Extract just the part of the backtrace that is "below"
    # the config file mentioned. If we can't find the config file
    # in the stack trace, we might return empty array.
    #
    # If the ruby supports Exception#backtrace_locations, the
    # returned array will actually be of Thread::Backtrace::Location elements.
    def self.backtrace_from_config(file_path, exception)
      filtered_trace = []
      found          = false

      # MRI 2.1+ has exception.backtrace_locations which makes
      # this a lot easier, but JRuby 1.7.x doesn't yet, so we
      # need to do it both ways.
      if (exception.respond_to?(:backtrace_locations) &&
          exception.backtrace_locations &&
          exception.backtrace_locations.length > 0)

        exception.backtrace_locations.each do |location|
          filtered_trace << location
          (found=true and break) if location.path == file_path
        end
      else
        filtered_trace = []
        exception.backtrace.each do |line|
          filtered_trace << line
          (found=true and break) if line.start_with?(file_path)
        end
      end

      return found ? filtered_trace : []
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
