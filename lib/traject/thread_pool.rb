require 'concurrent'
require 'thread' # for Queue

module Traject
  # An abstraction wrapping a Concurrent::ThreadPool in some configuration choices
  # and other apparatus.  Concurrent::ThreadPool is a Java ThreadPool executor on
  # jruby for performance, and is ruby-concurrent's own ruby implementation otherwise.
  #
  # 1) Initialize with chosen pool size -- we create fixed size pools, where
  # core and max sizes are the same.
  #
  # 2) If initialized with nil or 0 for threadcount,  no thread pool will actually
  # be created, and work sent to the Traject::ThreadPool will just be executed
  # in the caller thread. We call this a nil threadpool. One situation it can be useful
  # is if you are running under MRI, where multi-core parallelism isn't available, so
  # an actual threadpool may not be useful. (Although in some cases a thread pool,
  # especially one with size 1, can be useful in MRI for I/O blocking operations)
  #
  # 3) Use the #maybe_in_threadpool method to send blocks to thread pool for
  # execution -- if configurred with a nil threadcount, your block will just be
  # executed in calling thread. Be careful to not refer to any non-local
  # variables in the block, unless the variable has an object you can
  # use thread-safely!
  #
  # 4) We configure our underlying Concurrent::ThreadPool
  # with a work queue that will buffer up to (pool_size*3) tasks. If the queue is full,
  # the underlying Concurrent::ThreadPool is set up to use the :caller_runs policy
  # meaning the block will end up executing in caller's own thread. With the kind
  # of work we're doing, where each unit of work is small and there are many of them--
  # the :caller_runs policy serves as an effective 'back pressure' mechanism to keep
  # the work queue from getting too large and exhausting memory, when producers are
  # faster than consumers.
  #
  # 5) Any exceptions raised by pool-executed work are captured accumulated in a thread-safe
  #  manner, and can be re-raised in the thread of your choice by calling
  #  #raise_collected_exception!
  #
  # 6) When you are done with the threadpool, you can and must call
  #  #shutdown_and_wait, which will wait for all current queued work
  #  to complete, then return.  You can not give any more work to the pool
  #  after you do this. By default it'll wait pretty much forever, which should
  #  be fine. If you never call shutdown, then queued or in-progress work
  #  may be abandoned when the program ends, which would be bad.
  #
  # 7) We will keep track of total times a block is run in thread pool, and
  #  total elapsed (wall) time of running all blocks, so an average_execution_ms
  #  time can be given.  #average_execution_ms may be inaccurate if called when
  #  threads are still executing, as it's not entirely thread safe (may get
  #  an off by one as to total iterations)
  class ThreadPool
    attr_reader :pool_size, :queue_capacity

    @@disable_concurrency = false

    # Calling Traject::ThreadPool.disable_concurrency! permanently and irrevocably (for program execution)
    # forces all ThreadPools to have a pool_size of 0 -- running all work inline -- so should disable all
    # use of threads in Traject.
    def self.disable_concurrency! ;  @@disable_concurrency = true ; end
    def self.concurrency_disabled? ; @@disable_concurrency ; end

    # First arg is pool size, 0 or nil and we'll be a null/no-op pool which executes
    # work in caller thread.
    def initialize(pool_size)
      @thread_pool             = nil # assume we don't have one
      @exceptions_caught_queue = [] # start off without exceptions

      if self.class.concurrency_disabled?
        pool_size = 0
      end

      unless pool_size.nil? || pool_size == 0
        @pool_size      = pool_size.to_i
        @queue_capacity = pool_size * 3

        @thread_pool             = Concurrent::ThreadPoolExecutor.new(
            :min_threads     => @pool_size,
            :max_threads     => @pool_size,
            :max_queue       => @queue_capacity,
            :fallback_policy => :caller_runs
        )

        # A thread-safe queue to collect exceptions cross-threads.
        # We really only need to save the first exception, but a queue
        # is a convenient way to store a value concurrency-safely, and
        # might as well store all of them.
        @exceptions_caught_queue = Queue.new
      end
    end

    # Pass it a block, MAYBE gets executed in the bg in a thread pool. Maybe
    # gets executed in the calling thread.
    #
    # There are actually two 'maybes':
    #
    # * If Traject::ThreadPool was configured with null thread pool, then ALL
    #   work will be executed in calling thread.
    #
    # * If there is a thread pool, but it's work queue is full, then a job
    #   will be executed in calling thread (because we configured our java
    #   thread pool with a limited sized queue, and CallerRunsPolicy rejection strategy)
    #
    # You can pass arbitrary arguments to the method, that will then be passed
    # to your block -- similar to how ruby Thread.new works. This is convenient
    # for creating variables unique to the block that won't be shared outside
    # the thread:
    #
    #     thread_pool.maybe_in_thread_pool(x, y) do |x1, y1|
    #       100.times do
    #         something_with(x1)
    #       end
    #     end
    #     x = "someting else"
    #     # If we hadn't passed args with block, and had just
    #     # used x in the block, it'd be the SAME x as this one,
    #     # and would be pointing to a different string now!
    #
    #  Note, that just makes block-local variables, it doesn't
    #  help you with whether a data structure itself is thread safe.
    def maybe_in_thread_pool(*args)
      if @thread_pool
        @thread_pool.post do
          begin
            yield(*args)
          rescue Exception => e
            collect_exception(e)
          end
        end
      else
        yield(*args)
      end

    end


    # thread-safe way of storing an exception, to raise
    # later in a different thread. We don't guarantee
    # that we can store more than one at a time, only
    # the first one recorded may be stored.
    def collect_exception(e)
      @exceptions_caught_queue.push(e)
    end

    # If there's a stored collected exception, raise it
    # again now. Call this to re-raise exceptions caught in
    # other threads in the thread of your choice.
    #
    # If you call this method on a ThreadPool initialized with nil
    # as a non-functioning threadpool -- then this method is just
    # a no-op.
    def raise_collected_exception!
      unless @exceptions_caught_queue.empty?
        e = @exceptions_caught_queue.pop
        raise e
      end
    end

    # shutdown threadpool, and wait for all work to complete.
    # this one is also a no-op if you have a null ThreadPool that
    # doesn't really have a threadpool at all.
    #
    # returns elapsed time in seconds it took to shutdown
    def shutdown_and_wait
      start_t = Time.now

      if @thread_pool
        @thread_pool.shutdown
        @thread_pool.wait_for_termination
      end

      return (Time.now - start_t)
    end

  end
end
