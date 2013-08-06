# TODO: THREAD POOL
#
# 1) Exception handling in threads, what's the right thing to do
# 2) General count of failed records in a thread safe way, so we can report
#    it back from 'close', so process can report it back, and non-zero exit
#    code can be emited from command-line.
# 3) back pressure on thread pool. give it a bounded blocking queue instead,
#    to make sure thousands of add tasks don't build up, waiting until the end.
#    or does that even matter? So what if they build up in the queue and only
#    get taken care of at the end, is that okay? I do emit a warning right now
#    if it takes more than 60 seconds to process remaining thread pool task queue
#    at end.
# 4) No tests yet that actually test thread pool stuff; additionally, may make
#    some of the batch tests fail in non-deterministic ways, since batch tests
#    assume order of add (and our Mock solr server is not thread safe yet!)

require 'yell'

require 'traject'
require 'traject/util'
require 'traject/qualified_const_get'
require 'traject/thread_pool'

require 'uri'
require 'thread' # for Mutex

#
# Writes to a Solr using SolrJ, and the SolrJ HttpSolrServer.
#  (sub-class later for the ConcurrentUpdate server?)
#
# After you call #close, you can check #skipped_record_count if you want
# for an integer count of skipped records.
#
# For fatal errors that raise... async processing with thread_pool means that
# you may not get a raise immediately after calling #put, you may get it on
# a FUTURE #put or #close. You should get it eventually though.
#
# settings:
#   [solr.url] Your solr url (required)
#   [solrj_writer.server_class_name]  Defaults to "HttpSolrServer". You can specify
#                                   another Solr Server sub-class, but it has
#                                   to take a one-arg url constructor. Maybe
#                                   subclass this writer class and overwrite
#                                   instantiate_solr_server! otherwise
#   [solrj.jar_dir] Custom directory containing all of the SolrJ jars. All
#                   jars in this dir will be loaded. Otherwise,
#                   we load our own packaged solrj jars. This setting
#                   can't really be used differently in the same app instance,
#                   since jars are loaded globally.
#   [solrj_writer.parser_class_name] A String name of a class in package
#                                    org.apache.solr.client.solrj.impl,
#                                    we'll instantiate one with a zero-arg
#                                    constructor, and pass it as an arg to setParser on
#                                    the SolrServer instance, if present.
#                                    NOTE: For contacting a Solr 1.x server, with the
#                                    recent version of SolrJ used by default, set to
#                                    "XMLResponseParser"
#   [solrj_writer.commit_on_close]  If true (or string 'true'), send a commit to solr
#                                   at end of #process.
#   [solrj_writer.batch_size]       If non-nil and more than 1, send documents to
#                                   solr in batches of solrj_writer.batch_size. If nil/1,
#                                   however, an http transaction with solr will be done
#                                   per doc. DEFAULT to 100, which seems to be a sweet spot.
#   [solrj_writer.thread_pool]      Defaults to 4. A thread pool is used for submitting docs
#                                   to solr. Set to 0 or nil to disable threading. Set to 1,
#                                   there will still be a single bg thread doing the adds.
#                                   May make sense to set higher than number of cores on your
#                                   indexing machine, as these threads will mostly be waiting
#                                   on Solr. Speed/capacity of your solr is more relevant.
class Traject::SolrJWriter
  # just a tuple of a SolrInputDocument
  # and a Traject::Indexer::Context it came from
  class UpdatePackage
    attr_accessor :solr_document, :context
    def initialize(doc, ctx)
      self.solr_document = doc
      self.context = ctx
    end
  end

  include Traject::QualifiedConstGet

  attr_reader :settings

  attr_reader :batched_queue

  def initialize(argSettings)
    @settings = Traject::Indexer::Settings.new(argSettings)
    settings_check!(settings)

    ensure_solrj_loaded!

    solr_server # init

    @batched_queue = java.util.concurrent.LinkedBlockingQueue.new

    # when multi-threaded exceptions raised in threads are held here
    # we need a HIGH performance queue here to try and avoid slowing things down,
    # since we need to check it frequently.
    @async_exception_queue = java.util.concurrent.ConcurrentLinkedQueue.new

    # Store error count in an AtomicInteger, so multi threads can increment
    # it safely, if we're threaded.
    @skipped_record_incrementer = java.util.concurrent.atomic.AtomicInteger.new(0)

    # if our thread pool settings are 0, it'll just create a null threadpool that
    # executes in calling context.
    @thread_pool = Traject::ThreadPool.new( @settings["solrj_writer.thread_pool"].to_i )

    @debug_ascii_progress = (@settings["debug_ascii_progress"].to_s == "true")
  end

  # Loads solrj if not already loaded. By loading all jars found
  # in settings["solrj.jar_dir"]
  def ensure_solrj_loaded!
    unless defined?(HttpSolrServer) && defined?(SolrInputDocument)
      require 'java'

      tries = 0
      begin
        tries += 1
        java_import org.apache.solr.client.solrj.impl.HttpSolrServer
        java_import org.apache.solr.common.SolrInputDocument
      rescue NameError  => e
        # /Users/jrochkind/code/solrj-gem/lib"

        included_jar_dir = File.expand_path("../../vendor/solrj/lib", File.dirname(__FILE__))

        jardir = settings["solrj.jar_dir"] || included_jar_dir
        Dir.glob("#{jardir}/*.jar") do |x|
          require x
        end
        if tries > 1
          raise LoadError.new("Can not find SolrJ java classes")
        else
          retry
        end
      end
    end

    # And for now, SILENCE SolrJ logging
    org.apache.log4j.Logger.getRootLogger().addAppender(org.apache.log4j.varia.NullAppender.new)
  end

  # Method IS thread-safe, can be called concurrently by multi-threads.
  #
  # Why? If not using batched add, we just use the SolrServer, which is already
  # thread safe itself.
  #
  # If we are using batch add, we surround all access to our shared state batch queue
  # in a mutex -- just a naive implementation. May be able to improve performance
  # with more sophisticated java.util.concurrent data structure (blocking queue etc)
  # I did try a java ArrayBlockingQueue or LinkedBlockingQueue instead of our own
  # mutex -- I did not see consistently different performance. May want to
  # change so doesn't use a mutex at all if multiple mapping threads aren't being
  # used.
  #
  # this class does not at present use any threads itself, all work will be done
  # in the calling thread, including actual http transactions to solr via solrj SolrServer
  # if using batches, then not every #put is a http transaction, but when it is,
  # it's in the calling thread, synchronously.
  def put(context)
    @thread_pool.raise_collected_exception!

    # package the SolrInputDocument along with the context, so we have
    # the context for error reporting when we actually add.

    package = UpdatePackage.new(hash_to_solr_document(context.output_hash), context)

    if settings["solrj_writer.batch_size"].to_i > 1
      ready_batch = []

      # Synchronize access to our shared batched_queue state,
      # but once we've pulled out what we want in local var
      # `ready_batch`, don't need to synchronize anymore.
      batched_queue.add(package)
      if batched_queue.size >= settings["solrj_writer.batch_size"].to_i
        batched_queue.drain_to(ready_batch)
      end

      if ready_batch.length > 0
        if @debug_ascii_progress
          $stderr.write("^")
          if @thread_pool.queue && (@thread_pool.queue.size >= @thread_pool.queue_capacity)
            $stderr.write "!"
          end
        end

        @thread_pool.maybe_in_thread_pool { batch_add_document_packages(ready_batch) }        
      end
    else # non-batched add, add one at a time.
      @thread_pool.maybe_in_thread_pool { add_one_document_package(package) }
    end
  end

  def hash_to_solr_document(hash)
    doc = SolrInputDocument.new
    hash.each_pair do |key, value_array|
      value_array.each do |value|
        doc.addField( key, value )
      end
    end
    return doc
  end

  # Takes array and batch adds it to solr -- array of UpdatePackage tuples of
  # SolrInputDocument and context.
  #
  # Catches error in batch add, logs, and re-tries docs individually
  #
  # Is thread-safe, because SolrServer is thread-safe, and we aren't
  # referencing any other shared state. Important that CALLER passes
  # in a doc array that is not shared state, extracting it from
  # shared state batched_queue in a mutex.
  def batch_add_document_packages(current_batch)
    begin
      a = current_batch.collect {|package| package.solr_document }    
      solr_server.add( a )

      $stderr.write "%" if @debug_ascii_progress
    rescue Exception => e
      # Error in batch, none of the docs got added, let's try to re-add
      # em all individually, so those that CAN get added get added, and those
      # that can't get individually logged.
      logger.warn "Error encountered in batch solr add, will re-try documents individually, at a performance penalty...\n" + Traject::Util.exception_to_log_message(e)
      current_batch.each do |package|
        add_one_document_package(package)
      end
    end
  end


  # Adds a single SolrInputDocument passed in as an UpdatePackage combo of SolrInputDocument
  # and context.
  #
  # Rescues exceptions thrown by SolrServer.add, logs them, and then raises them
  # again if deemed fatal and should stop indexing. Only intended to be used on a SINGLE
  # document add. If we get an exception on a multi-doc batch add, we need to recover
  # differently.
  def add_one_document_package(package)
    begin
      solr_server.add(package.solr_document)
    # Honestly not sure what the difference is between those types, but SolrJ raises both
    rescue org.apache.solr.common.SolrException, org.apache.solr.client.solrj.SolrServerException  => e
      id        = package.context.source_record && package.context.source_record['001'] && package.context.source_record['001'].value
      id_str    = id ? "001:#{id}" : ""

      position  = package.context.position
      position_str = position ? "at file position #{position} (starting at 1)" : ""

      logger.error("Could not index record #{id_str} #{position_str}\n" + Traject::Util.exception_to_log_message(e) )
      logger.debug(package.context.source_record.to_s)

      @skipped_record_incrementer.getAndIncrement() # AtomicInteger, thread-safe increment.

      if fatal_exception? e
        logger.fatal ("SolrJ exception judged fatal, raising...")
        raise e
      end
    end
  end

  def logger
    settings["logger"] ||=  Yell.new(STDERR, :level => "gt.fatal") # null logger
  end

  # If an exception is encountered talking to Solr, is it one we should
  # entirely give up on? SolrJ doesn't use a useful exception class hieararchy,
  # we have to look into it's details and guess.
  def fatal_exception?(e)


    root_cause = e.respond_to?(:getRootCause) && e.getRootCause

    # Various kinds of inability to actually talk to the
    # server look like this:
    if root_cause.kind_of? java.io.IOException
      return true
    end

    return false
  end

  def close
    @thread_pool.raise_collected_exception!

    # Any leftovers in batch buffer? Send em to the threadpool too.
    if batched_queue.length > 0
      packages = []
      batched_queue.drain_to(packages)

      # we do it in the thread pool for consistency, and so
      # it goes to the end of the queue behind any outstanding
      # work in the pool.
      @thread_pool.maybe_in_thread_pool { batch_add_document_packages( packages ) }
    end

    # Wait for shutdown, and time it.
    logger.debug "SolrJWriter: Shutting down thread pool, waiting if needed..."
    elapsed = @thread_pool.shutdown_and_wait
    if elapsed > 60
      logger.warn "Waited #{elapsed} seconds for all SolrJWriter threads, you may want to increase solrj_writer.thread_pool (currently #{@settings["solrj_writer.thread_pool"]})"
    end
    logger.debug "SolrJWriter: Thread pool shutdown complete"
    logger.warn "SolrJWriter: #{skipped_record_count} skipped records" if skipped_record_count > 0

    # check again now that we've waited, there could still be some
    # that didn't show up before.
    @thread_pool.raise_collected_exception!

    if settings["solrj_writer.commit_on_close"].to_s == "true"
      logger.info "SolrJWriter: Sending commit to solr..."
      solr_server.commit
    end

    solr_server.shutdown
    @solr_server = nil
  end

  # Return count of encountered skipped records. Most accurate to call
  # it after #close, in which case it should include full count, even
  # under async thread_pool.
  def skipped_record_count
    @skipped_record_incrementer.get
  end


  def solr_server
    @solr_server ||= instantiate_solr_server!
  end
  attr_writer :solr_server # mainly for testing

  # Instantiates a solr server of class settings["solrj_writer.server_class_name"] or "HttpSolrServer"
  # and initializes it with settings["solr.url"]
  def instantiate_solr_server!
    server_class  = qualified_const_get( settings["solrj_writer.server_class_name"] || "HttpSolrServer" )
    server        = server_class.new( settings["solr.url"].to_s );

    if parser_name = settings["solrj_writer.parser_class_name"]
      #parser = org.apache.solr.client.solrj.impl.const_get(parser_name).new
      parser = Java::JavaClass.for_name("org.apache.solr.client.solrj.impl.#{parser_name}").ruby_class.new
      server.setParser( parser )
    end

    server
  end

  def settings_check!(settings)
    unless settings.has_key?("solr.url") && ! settings["solr.url"].nil?
      raise ArgumentError.new("SolrJWriter requires a 'solr.url' solr url in settings")
    end

    unless settings["solr.url"] =~ /^#{URI::regexp}$/
      raise ArgumentError.new("SolrJWriter requires a 'solr.url' setting that looks like a URL, not: `#{settings['solr.url']}`")
    end
  end

end
