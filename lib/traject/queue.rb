require 'thread'


# Extend the normal queue class with some useful methods derived from
# its java counterpart

class Traject::Queue < Queue

  alias_method :put, :enq
  alias_method :take, :deq

  def initialize(*args)
    super
    @mutex = Mutex.new
  end


  # Drain it to an array (or, really, anything that response to <<)
  def drain_to(a)
    @mutex.synchronize do
      self.size.times do
        a << self.pop
      end
    end
    a
  end


  def to_a
    a = []
    @mutex.synchronize do
      self.size.times do
        elem = self.pop
        a << elem
        self.push elem
      end
    end
    a
  end
  alias_method :to_array, :to_a




  # Check out the first element. Hideously expensive
  # because we have to drain it and then put it all
  # back together to maintain order

  def peek
    first = nil
    @mutex.synchronize do
      first = self.pop
      self.push(first)
      (self.size - 1).times do
        self.push self.pop
      end
    end
    first
  end


end
