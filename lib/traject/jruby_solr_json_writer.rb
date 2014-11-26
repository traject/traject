require 'yell'

require 'traject'
require 'traject/util'
require 'traject/qualified_const_get'
require 'traject/thread_pool'

require 'json'
require 'httpclient'

require 'uri'
require 'thread' # for Mutex


class Traject::JRubySolrJSONWriter
  include Traject::QualifiedConstGet

  attr_reader :settings
  attr_reader :batched_queue


  def initialize(argSettings)
    @settings = Traject::Indexer::Settings.new(argSettings)
    settings_check!(settings)

    @http_client = HTTPClient.new
    @batched_queue = java.util.concurrent.LinkedBlockingQueue.new
    @batch_size = settings["solrj_writer.batch_size"].to_i
    @batch_size = 1 if @batch_size == 0


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
    @solr_update_url = [settings['solr.url'].chomp('/'), 'update', 'json'].join('/')
    logger.info("   #{self.class.name} writing to '#{@solr_update_url}'")
  end



  def put(context)
    @batched_queue << context
    if @batched_queue.size >= @batch_size
      batch = []
      @batched_queue.drain_to(batch)
      @thread_pool.maybe_in_thread_pool { send_batch(batch) }
    end
  end

  def send_batch(batch)
    return if batch.empty?
    json_package = JSON.generate(batch.map{|c| c.output_hash})
    begin
      resp = @http_client.post @solr_update_url, json_package, "Content-type" => "application/json"
    rescue StandardError => exception
    end
    if exception || resp.status != 200
      logger.error "Error in batch. Sending one at a time"
      batch.each do |c|
        send_single(c)
      end
    end
  end


  def send_single(c)
    json_package = [JSON.generate(c.output_hash)]
    begin
      resp = @http_client.post @solr_update_url, json_package, "Content-type" => "application/json"
    rescue StandardError => exception
    end
    if exception || resp.status != 200
      id = c.output_hash['id'] || "<no id field found>"
      if exception
        msg = "(#{exception.class}) #{exception.message}"
      else
        msg = resp.body
      end
      logger.error "Error indexing record #{id} at position #{c.position}: #{msg}"
      @skipped_record_incrementer.getAndIncrement()
    end

  end



  def logger
    settings["logger"] ||=  Yell.new(STDERR, :level => "gt.fatal") # null logger
  end


  def close
    @thread_pool.raise_collected_exception!
    # Finish off whatever's left
    batch = []
    @batched_queue.drain_to(batch)
    send_batch(batch)

    # Wait for shutdown, and time it.
    logger.debug "JRubySolrJSONWriter: Shutting down thread pool, waiting if needed..."
    elapsed = @thread_pool.shutdown_and_wait
    if elapsed > 60
      logger.warn "Waited #{elapsed} seconds for all JRubySolrJSONWriter threads, you may want to increase solrj_writer.thread_pool (currently #{@settings["solrj_writer.thread_pool"]})"
    end
    logger.debug "JRubySolrJSONWriter: Thread pool shutdown complete"
    logger.warn "JRubySolrJSONWriter: #{skipped_record_count} skipped records" if skipped_record_count > 0

    # check again now that we've waited, there could still be some
    # that didn't show up before.
    @thread_pool.raise_collected_exception!

    if settings["solrj_writer.commit_on_close"].to_s == "true"
      commit_url = settings["solr.url"].chomp("/") + "/update?commit=true"
      logger.info "JRubySolrJSONWriter: Sending commit to solr..."
      resp = @http_client.get commit_url
      if resp.status != 200
        logger.error("Error sending commit to Solr: #{resp.status} #{resp.body}")
      end

    end
  end

  # Return count of encountered skipped records. Most accurate to call
  # it after #close, in which case it should include full count, even
  # under async thread_pool.
  def skipped_record_count
    @skipped_record_incrementer.get
  end

  def settings_check!(settings)
    unless settings.has_key?("solr.url") && ! settings["solr.url"].nil?
      raise ArgumentError.new("JRubySolrJSONWriter requires a 'solr.url' solr url in settings")
    end

    unless settings["solr.url"] =~ /^#{URI::regexp}$/
      raise ArgumentError.new("JRubySolrJSONWriter requires a 'solr.url' setting that looks like a URL, not: `#{settings['solr.url']}`")
    end
  end

end
