require 'yell'

require 'traject'
require 'traject/util'
require 'traject/qualified_const_get'
require 'traject/thread_pool'
require 'traject/queue'

require 'json'
require 'httpclient'

require 'uri'
require 'thread'     # for Mutex/Queue
require 'concurrent' # for atomic_fixnum

# Write to Solr using the JSON interface; only works for Solr >= 3.2
#
# This should work under both MRI and JRuby, with JRuby getting much
# better performance due to the threading model.
#
# Relevant settings
#
# * solr.url (optional if solr.update_url is set) The URL to the solr core to index into
#
# * solr.update_url The actual update url. If unset, we'll first see if
#   "#{solr.url}/update/json" exists, and if not use "#{solr.url}/update"
#
# * solr_writer.batch_size How big a batch to send to solr. Default is 100.
#   My tests indicate that this setting doesn't change overall index speed by a ton.
#
# * solr_writer.thread_pool How many threads to use for the writer. Default is 1.
#
# * solr_writer.commit_on_close Set to true (or "true") if you want to commit at the
#   end of the indexing run
#
# * solr_writer.max_errors How many errors before we bail out and assume something
#   more serious is wrong? Set to -1 to disable checks. Default 500


class Traject::SolrJsonWriter
  include Traject::QualifiedConstGet

  DEFAULT_MAX_ERRORS = 500
  DEFAULT_BATCH_SIZE = 100

  # The passed-in settings
  attr_reader :settings

  # A queue to hold documents before sending to solr
  attr_reader :batched_queue


  def initialize(argSettings)
    @settings = Traject::Indexer::Settings.new(argSettings)

    # Set max errors
    @max_errors = (@settings['solr_writer.max_errors'] || DEFAULT_MAX_ERRORS).to_i
    if @max_errors <= 0
      @max_errors = nil
    end

    @http_client = HTTPClient.new

    @batch_size = (settings["solr_writer.batch_size"] || DEFAULT_BATCH_SIZE).to_i
    @batch_size = 1 if @batch_size == 0

    # Store error count in an AtomicInteger, so multi threads can increment
    # it safely, if we're threaded.
    @skipped_record_incrementer = Concurrent::AtomicFixnum.new(0)


    # How many threads to use for the writer?
    thread_pool_size = @settings["solr_writer.thread_pool"]
    if defined? thread_pool_size
      thread_pool_size = thread_pool_size.to_i
    else
      thread_pool_size = 1
    end

    @batched_queue         = Traject::Queue.new # need #drain_to
    @async_exception_queue = Queue.new
    @thread_pool = Traject::ThreadPool.new(thread_pool_size)

    # if our thread pool settings are 0, it'll just create a null threadpool that
    # executes in calling context.

    # Figure out where to send updates
    @solr_update_url = self.determine_solr_update_url


    logger.info("   #{self.class.name} writing to '#{@solr_update_url}' in batches of #{@batch_size}")
  end


  # Add a single context to the queue, ready to be sent to solr
  def put(context)
    @batched_queue << context
    if @batched_queue.size >= @batch_size
      batch = []
      @batched_queue.drain_to(batch)
      @thread_pool.maybe_in_thread_pool { send_batch(batch) }
    end
  end

  # Send the given batch of contexts. If something goes wrong, send
  # them one at a time.
  # @param [Array<Traject::Indexer::Context>] an array of contexts
  def send_batch(batch)
    return if batch.empty?
    json_package = JSON.generate(batch.map { |c| c.output_hash })
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


  # Send a single context to Solr, logging an error if need be
  # @param [Traject::Indexer::Context] c The context whose document you want to send
  def send_single(c)
    json_package = JSON.generate([c.output_hash])
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

      @skipped_record_incrementer.increment
      if @max_errors and skipped_record_count > @max_errors
          raise RuntimeError.new("Exceeded maximum number of errors (#{@max_errors}): aborting")
      end

    end

  end


  # Get the logger from the settings, or build one if necessary
  def logger
    settings["logger"] ||= Yell.new(STDERR, :level => "gt.fatal") # null logger
  end


  # On close, we need to (a) raise any exceptions we might have, (b) send off
  # the last (possibly empty) batch, and (c) commit if instructed to do so
  # via the solr_writer.commit_on_close setting.
  def close
    @thread_pool.raise_collected_exception!
    # Finish off whatever's left
    batch = []
    @batched_queue.drain_to(batch)
    send_batch(batch)

    # Wait for shutdown, and time it.
    logger.debug "#{self.class.name}: Shutting down thread pool, waiting if needed..."
    elapsed = @thread_pool.shutdown_and_wait
    if elapsed > 60
      logger.warn "Waited #{elapsed} seconds for all threads, you may want to increase solr_writer.thread_pool (currently #{@settings["solr_writer.thread_pool"]})"
    end
    logger.debug "#{self.class.name}: Thread pool shutdown complete"
    logger.warn "#{self.class.name}: #{skipped_record_count} skipped records" if skipped_record_count > 0

    # check again now that we've waited, there could still be some
    # that didn't show up before.
    @thread_pool.raise_collected_exception!

    # Commit if we're supposed to
    commit if settings["solr_writer.commit_on_close"].to_s == "true"
  end


  # Send a commit
  def commit
    logger.info "#{self.class.name} sending commit to solr at url #{@solr_update_url}"
    resp = @http_client.get(@solr_update_url, {:commit => 'true'})
    unless resp.status == 200
      logger.error("Problems with commit: #{resp.status} #{resp.body}")
    end
  end


  # Return count of encountered skipped records. Most accurate to call
  # it after #close, in which case it should include full count, even
  # under async thread_pool.
  def skipped_record_count
    @skipped_record_incrementer.value
  end


  # Relatively complex logic to determine if we have a valid URL and what it is
  def determine_solr_update_url
    if settings['solr.update_url']
      check_solr_update_url(settings['solr.update_url'])
    else
      derive_solr_update_url_from_solr_url(settings['solr.url'])
    end
  end


  # If we've got a solr.update_url, make sure it's ok
  def check_solr_udpate_url
    unless url =~ /^#{URI::regexp}$/
      raise ArgumentError.new("#{self.class.name} setting `solr.update_url` doesn't look like a URL: `#{url}`")
    end
    url
  end

  def derive_solr_update_url_from_solr_url(url)
    # Nil? Then we bail
    if url.nil?
      raise ArgumentError.new("#{self.class.name}: Neither solr.update_url nor solr.url set; need at least one")
    end

    # Not a URL? Bail
    unless url =~ /^#{URI::regexp}$/
      raise ArgumentError.new("#{self.class.name} setting `solr.url` doesn't look like a URL: `#{url}`")
    end

    # First, try the /update/json handler
    candidate = [url.chomp('/'), 'update', 'json'].join('/')
    resp      = @http_client.get(candidate)
    if resp.status == 404
      candidate = [url.chomp('/'), 'update'].join('/')
    end
    candidate
  end


end
