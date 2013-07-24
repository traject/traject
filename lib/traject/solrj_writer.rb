require 'yell'

require 'traject'
require 'traject/qualified_const_get'

require 'uri'
require 'thread' # for Mutex

#
# Writes to a Solr using SolrJ, and the SolrJ HttpSolrServer.
#  (sub-class later for the ConcurrentUpdate server?)
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
class Traject::SolrJWriter
  include Traject::QualifiedConstGet

  attr_reader :settings

  attr_accessor :batched_queue

  def initialize(argSettings)
    @settings = argSettings
    settings_check!(settings)

    ensure_solrj_loaded!

    solr_server # init

    self.batched_queue = []
    @batched_queue_mutex = Mutex.new
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
  #
  # this class does not at present use any threads itself, all work will be done
  # in the calling thread, including actual http transactions to solr via solrj SolrServer
  # if using batches, then not every #put is a http transaction, but when it is,
  # it's in the calling thread, synchronously.
  def put(hash)
    doc = hash_to_solr_document(hash)

    if settings["solrj_writer.batch_size"].to_i > 1
      ready_batch = nil

      # Synchronize access to our shared batched_queue state,
      # but once we've pulled out what we want in local var
      # `ready_batch`, don't need to synchronize anymore.
      @batched_queue_mutex.synchronize do
        batched_queue << doc
        if batched_queue.length >= settings["solrj_writer.batch_size"].to_i
          ready_batch = batched_queue.slice!(0, batched_queue.length)
        end
      end

      if ready_batch
        batch_add_documents(ready_batch)
      end
    else # non-batched add, add one at a time.
      rescue_solr_single_add_exception do
        solr_server.add(doc)
      end
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

  # Takes array and batch adds it to solr
  #
  # Catches error in batch add, logs, and re-tries docs individually
  #
  # Is thread-safe, because SolrServer is thread-safe, and we aren't
  # referencing any other shared state. Important that CALLER passes
  # in a doc array that is not shared state, extracting it from
  # shared state batched_queue in a mutex.
  def batch_add_documents(current_batch)
    logger.debug("SolrJWriter: batch adding #{current_batch.length} documents")
    begin
      solr_server.add( current_batch )
    rescue Exception => e
      # Error in batch, none of the docs got added, let's try to re-add
      # em all individually, so those that CAN get added get added, and those
      # that can't get individually logged.
      logger.warn "Error encountered in batch solr add, will re-try documents individually, at a performance penalty...\n" + exception_to_log_message(e)
      current_batch.each do |doc|
        rescue_solr_single_add_exception do
          solr_server.add(doc)
        end
      end
    end
  end

  # Rescues exceptions thrown by SolrServer.add, logs them, and then raises them
  # again if deemed fatal and should stop indexing. Only intended to be used on a SINGLE
  # document add. If we get an exception on a multi-doc batch add, we need to recover
  # differently.
  #
  # eg
  #
  # rescue_solr_single_add_exception do
  #   solr_server.add(doc)
  # end
  def rescue_solr_single_add_exception
    begin
      yield
    rescue org.apache.solr.common.SolrException, org.apache.solr.client.solrj.SolrServerException  => e
      # Honestly not sure what the difference is between those types, but SolrJ raises both
      logger.error("Could not index record\n" + exception_to_log_message(e) )

      if fatal_exception? e
        logger.fatal ("SolrJ exception judged fatal, raising...")
        raise e
      end
    end
  end

  def logger
    settings["logger"] ||= Yell.new(STDERR, :level => "gt.fatal") # null logger
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

  def exception_to_log_message(e)
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

  def close
    if batched_queue.length > 0
      # leftovers
      batch_add_documents( batched_queue.dup )
      batched_queue.clear
    end

    if settings["solrj_writer.commit_on_close"].to_s == "true"
      logger.info "SolrJWriter: Sending commit to solr..."
      solr_server.commit
    end

    solr_server.shutdown
    @solr_server = nil
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