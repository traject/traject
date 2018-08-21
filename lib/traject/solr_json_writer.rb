require 'yell'

require 'traject/util'
require 'traject/qualified_const_get'
require 'traject/thread_pool'

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
# * solr.update_url: The actual update url. If unset, we'll first see if
#   "#{solr.url}/update/json" exists, and if not use "#{solr.url}/update"
#
# * solr_writer.batch_size: How big a batch to send to solr. Default is 100.
#   My tests indicate that this setting doesn't change overall index speed by a ton.
#
# * solr_writer.thread_pool: How many threads to use for the writer. Default is 1.
#   Likely useful even under MRI since thread will be waiting on Solr for some time.
#
# * solr_writer.max_skipped: How many records skipped due to errors before we
#   bail out with a fatal error? Set to -1 for unlimited skips. Default 0,
#   raise and abort on a single record that could not be added to Solr.
#
# * solr_writer.skippable_exceptions: List of classes that will be rescued internal to
#   SolrJsonWriter, and handled with max_skipped logic. Defaults to
#   `[HTTPClient::TimeoutError, SocketError, Errno::ECONNREFUSED]`
#
# * solr_writer.commit_on_close: Set to true (or "true") if you want to commit at the
#   end of the indexing run. (Old "solrj_writer.commit_on_close" supported for backwards
#   compat only.)
#
# * solr_writer.commit_timeout: If commit_on_close, how long to wait for Solr before
#   giving up as a timeout. Default 10 minutes. Solr can be slow.
#
# * solr_json_writer.http_client Mainly intended for testing, set your own HTTPClient
#   or mock object to be used for HTTP.


class Traject::SolrJsonWriter
  include Traject::QualifiedConstGet

  URI_REGEXP = URI::Parser.new.make_regexp.freeze

  DEFAULT_MAX_SKIPPED = 0
  DEFAULT_BATCH_SIZE  = 100

  # The passed-in settings
  attr_reader :settings, :thread_pool_size

  # A queue to hold documents before sending to solr
  attr_reader :batched_queue

  def initialize(argSettings)
    @settings = Traject::Indexer::Settings.new(argSettings)

    # Set max errors
    @max_skipped = (@settings['solr_writer.max_skipped'] || DEFAULT_MAX_SKIPPED).to_i
    if @max_skipped < 0
      @max_skipped = nil
    end

    @http_client = @settings["solr_json_writer.http_client"] || HTTPClient.new

    @batch_size = (settings["solr_writer.batch_size"] || DEFAULT_BATCH_SIZE).to_i
    @batch_size = 1 if @batch_size < 1

    # Store error count in an AtomicInteger, so multi threads can increment
    # it safely, if we're threaded.
    @skipped_record_incrementer = Concurrent::AtomicFixnum.new(0)


    # How many threads to use for the writer?
    # if our thread pool settings are 0, it'll just create a null threadpool that
    # executes in calling context.
    @thread_pool_size = (@settings["solr_writer.thread_pool"] || 1).to_i

    @batched_queue         = Queue.new
    @thread_pool = Traject::ThreadPool.new(@thread_pool_size)

    # old setting solrj_writer supported for backwards compat, as we make
    # this the new default writer.
    @commit_on_close = (settings["solr_writer.commit_on_close"] || settings["solrj_writer.commit_on_close"]).to_s == "true"

    # Figure out where to send updates
    @solr_update_url = self.determine_solr_update_url

    logger.info("   #{self.class.name} writing to '#{@solr_update_url}' in batches of #{@batch_size} with #{@thread_pool_size} bg threads")
  end


  # Add a single context to the queue, ready to be sent to solr
  def put(context)
    @thread_pool.raise_collected_exception!

    @batched_queue << context
    if @batched_queue.size >= @batch_size
      batch = Traject::Util.drain_queue(@batched_queue)
      @thread_pool.maybe_in_thread_pool(batch) {|batch_arg| send_batch(batch_arg) }
    end
  end

  # Not part of standard writer API.
  #
  # If we are batching adds, and have some not-yet-written ones queued up --
  # flush em all to solr.
  #
  # This should be thread-safe to call, but the write does take place in
  # the caller's thread, no threading is done for you here, regardless of setting
  # of solr_writer.thread_pool
  def flush
    send_batch( Traject::Util.drain_queue(@batched_queue) )
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
      error_message = exception ?
        Traject::Util.exception_to_log_message(exception) :
        "Solr response: #{resp.status}: #{resp.body}"

      logger.error "Error in Solr batch add. Will retry documents individually at performance penalty: #{error_message}"

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
      # Catch Timeouts and network errors as skipped records, but otherwise
      # allow unexpected errors to propagate up.
    rescue *skippable_exceptions => exception
      # no body, local variable exception set above will be used below
    end

    if exception || resp.status != 200
      if exception
        msg = Traject::Util.exception_to_log_message(exception)
      else
        msg = "Solr error response: #{resp.status}: #{resp.body}"
      end
      logger.error "Could not add record #{c.record_inspect}: #{msg}"
      logger.debug(c.source_record.to_s)

      @skipped_record_incrementer.increment
      if @max_skipped and skipped_record_count > @max_skipped
        raise MaxSkippedRecordsExceeded.new("#{self.class.name}: Exceeded maximum number of skipped records (#{@max_skipped}): aborting")
      end

    end

  end


  # Get the logger from the settings, or default to an effectively null logger
  def logger
    settings["logger"] ||= Yell.new(STDERR, :level => "gt.fatal") # null logger
  end

  # On close, we need to (a) raise any exceptions we might have, (b) send off
  # the last (possibly empty) batch, and (c) commit if instructed to do so
  # via the solr_writer.commit_on_close setting.
  def close
    @thread_pool.raise_collected_exception!

    # Finish off whatever's left. Do it in the thread pool for
    # consistency, and to ensure expected order of operations, so
    # it goes to the end of the queue behind any other work.
    batch = Traject::Util.drain_queue(@batched_queue)
    if batch.length > 0
      @thread_pool.maybe_in_thread_pool { send_batch(batch) }
    end

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
    if @commit_on_close
      commit
    end
  end


  # Send a commit
  def commit
    logger.info "#{self.class.name} sending commit to solr at url #{@solr_update_url}..."

    original_timeout = @http_client.receive_timeout

    @http_client.receive_timeout = (settings["commit_timeout"] || (10 * 60)).to_i

    resp = @http_client.get(@solr_update_url, {"commit" => 'true'})
    unless resp.status == 200
      raise RuntimeError.new("Could not commit to Solr: #{resp.status} #{resp.body}")
    end

    @http_client.receive_timeout = original_timeout
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
  def check_solr_update_url(url)
    unless /^#{URI_REGEXP}$/.match(url)
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
    unless  /^#{URI_REGEXP}$/.match(url)
      raise ArgumentError.new("#{self.class.name} setting `solr.url` doesn't look like a URL: `#{url}`")
    end

    # Assume the /update/json handler
    return [url.chomp('/'), 'update', 'json'].join('/')
  end

  class MaxSkippedRecordsExceeded < RuntimeError ; end


  private

  def skippable_exceptions
    @skippable_exceptions ||= (settings["solr_writer.skippable_exceptions"] || [HTTPClient::TimeoutError, SocketError, Errno::ECONNREFUSED])
  end
end
