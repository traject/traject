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
  end
end