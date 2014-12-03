require 'thread'


# Extend the normal queue class with some useful methods derived from
# its java counterpart


if defined? JRUBY_VERSION
  Traject::Queue = java.util.concurrent.LinkedBlockingQueue
else
  class Traject::Queue < Queue

    alias_method :put, :enq
    alias_method :take, :deq

    def initialize(*args)
      super
      @mutex = Mutex.new
    end


    # Drain it to an array (or, really, anything that response to <<)
    # Only take out what we had when we started, and if we run out of
    # stuff, well, just return what we actually managed to get.

    def drain_to(a)
      current_size = self.size
      begin
        current_size.times do
          a << self.deq(:throw_error_if_empty)
        end
      rescue ThreadError
      end
      current_size
    end
  end
end
