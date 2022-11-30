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
# Solr updates are by default sent with no commit params. This will definitely
# maximize your performance, and *especially* for bulk/batch indexing is recommended --
# use Solr auto commit in your Solr configuration instead, possibly with `commit_on_close`
# setting here.
#
# However, if you want the writer to send `commitWithin=true`, `commit=true`,
# `softCommit=true`, or any other URL parameters valid for Solr update handlers,
# you can configure this with `solr_writer.solr_update_args` setting. See:
# https://lucene.apache.org/solr/guide/7_0/near-real-time-searching.html#passing-commit-and-commitwithin-parameters-as-part-of-the-url
# Eg:
#
#     settings do
#       provide "solr_writer.solr_update_args", { commitWithin: 1000 }
#     end
#
#  (That it's a hash makes it infeasible to set/override on command line, if this is
#  annoying for you let us know)
#
#  `solr_update_args` will apply to batch and individual update requests, but
#  not to commit sent if `commit_on_close`. You can also instead set
#   `solr_writer.solr_commit_args` for that (or pass in an arg to #commit if calling
#   manually)
#
# ## Relevant settings
#
# * solr.url (optional if solr.update_url is set) The URL to the solr core to index into.
#   (Can include embedded HTTP basic auth as eg `http://user:pass@host/solr`)
#
# * solr.update_url: The actual update url. If unset, we'll first see if
#   "#{solr.url}/update/json" exists, and if not use "#{solr.url}/update". (Can include
#   embedded HTTP basic auth as eg `http://user:pass@host/solr)
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
#   `[HTTPClient::TimeoutError, SocketError, Errno::ECONNREFUSED, Traject::SolrJsonWriter::BadHttpResponse]`
#
# * solr_writer.solr_update_args: A _hash_ of query params to send to solr update url.
#   Will be sent with every update request. Eg `{ softCommit: true }` or `{ commitWithin: 1000 }`.
#   See also `solr_writer.solr_commit_args`
#
# * solr_writer.commit_on_close: Set to true (or "true") if you want to commit at the
#   end of the indexing run. (Old "solrj_writer.commit_on_close" supported for backwards
#   compat only.)
#
# * solr_writer.commit_solr_update_args: A hash of query params to send when committing.
#   Will be used for automatic `close_on_commit`, as well as any manual calls to #commit.
#   If set, must include {"commit" => "true"} or { "softCommit" => "true" } if you actually
#   want commits to happen when SolrJsonWriter tries to commit! But can be used to switch to softCommits
#   (hard commits default), or specify additional params like optimize etc.
#
# * solr_writer.http_timeout: Value in seconds, will be set on the httpclient as connect/receive/send
#   timeout. No way to set them individually at present. Default nil, use HTTPClient defaults
#   (60 for connect/recieve, 120 for send).
#
# * solr_writer.commit_timeout: If commit_on_close, how long to wait for Solr before
#   giving up as a timeout (http client receive_timeout). Default 10 minutes. Solr can be slow at commits. Overrides solr_writer.timeout
#
# * solr_json_writer.http_client Mainly intended for testing, set your own HTTPClient
#   or mock object to be used for HTTP.
#
# * solr_json_writer.use_packaged_certs: unlikely to be needed, set to true for legacy
#   behavior, to use packaged HTTPClient gem ssl certs. https://github.com/nahi/httpclient/issues/445
#
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


    # Figure out where to send updates, and if with basic auth
    @solr_update_url, basic_auth_user, basic_auth_password = self.determine_solr_update_url

    @http_client = if @settings["solr_json_writer.http_client"]
      @settings["solr_json_writer.http_client"]
    else
      client = HTTPClient.new

      # By default we'll use teh host OS SSL certs, but you can use
      # setting solr_json_writer.use_packaged_certs to true or "true"
      # to go back to previous behavior if you have a perverse reason to.
      # https://github.com/nahi/httpclient/issues/445
      unless @settings["solr_json_writer.use_packaged_certs"].to_s == "true"
        client.ssl_config.set_default_paths
      end

      if @settings["solr_writer.http_timeout"]
        client.connect_timeout = client.receive_timeout = client.send_timeout = @settings["solr_writer.http_timeout"]
      end

      if basic_auth_user || basic_auth_password
        client.set_auth(@solr_update_url, basic_auth_user, basic_auth_password)
      end

      client
    end

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


    @solr_update_args = settings["solr_writer.solr_update_args"]
    @commit_solr_update_args = settings["solr_writer.commit_solr_update_args"]

    logger.info("   #{self.class.name} writing to '#{@solr_update_url}' #{"(with HTTP basic auth)" if basic_auth_user || basic_auth_password}in batches of #{@batch_size} with #{@thread_pool_size} bg threads")
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

  # configured update url, with either settings @solr_update_args or passed in
  # query_params added to it
  def solr_update_url_with_query(query_params)
    if query_params
      @solr_update_url + '?' + URI.encode_www_form(query_params)
    else
      @solr_update_url
    end
  end

  # Send the given batch of contexts. If something goes wrong, send
  # them one at a time.
  # @param [Array<Traject::Indexer::Context>] an array of contexts
  def send_batch(batch)
    return if batch.empty?

    logger.debug("#{self.class.name}: sending batch of #{batch.size} to Solr")

    json_package = JSON.generate(batch.map { |c| c.output_hash })

    begin
      resp = @http_client.post solr_update_url_with_query(@solr_update_args), json_package, "Content-type" => "application/json"
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
    logger.debug("#{self.class.name}: sending single record to Solr: #{c.output_hash}")

    json_package = JSON.generate([c.output_hash])
    begin
      post_url = solr_update_url_with_query(@solr_update_args)
      resp = @http_client.post post_url, json_package, "Content-type" => "application/json"

      unless resp.status == 200
        raise BadHttpResponse.new("Unexpected HTTP response status #{resp.status} from POST #{post_url}", resp)
      end

      # Catch Timeouts and network errors -- as well as non-200 http responses --
      # as skipped records, but otherwise allow unexpected errors to propagate up.
    rescue *skippable_exceptions => exception
      msg = if exception.kind_of?(BadHttpResponse)
        "Solr error response: #{exception.response.status}: #{exception.response.body}"
      else
        Traject::Util.exception_to_log_message(exception)
      end

      logger.error "Could not add record #{c.record_inspect}: #{msg}"
      logger.debug("\t" + exception.backtrace.join("\n\t")) if exception
      logger.debug(c.source_record.to_s) if c.source_record

      @skipped_record_incrementer.increment
      if @max_skipped and skipped_record_count > @max_skipped
        # re-raising in rescue means the last encountered error will be available as #cause
        # on raised exception, a feature in ruby 2.1+.
        raise MaxSkippedRecordsExceeded.new("#{self.class.name}: Exceeded maximum number of skipped records (#{@max_skipped}): aborting: #{exception.message}")
      end
    end
  end


  # Very beginning of a delete implementation. POSTs a delete request to solr
  # for id in arg (value of Solr UniqueID field, usually `id` field).
  #
  # Right now, does it inline and immediately, no use of background threads or batching.
  # This could change.
  #
  # Right now, if unsuccesful for any reason, will raise immediately out of here.
  # Could raise any of the `skippable_exceptions` (timeouts, network errors), an
  # exception will be raised right out of here.
  #
  # Will use `solr_writer.solr_update_args` settings.
  #
  # There is no built-in way to direct a record to be deleted from an indexing config
  # file at the moment, this is just a loose method on the writer.
  def delete(id)
    logger.debug("#{self.class.name}: Sending delete to Solr for #{id}")

    json_package = {delete: id}
    resp = @http_client.post solr_update_url_with_query(@solr_update_args), JSON.generate(json_package), "Content-type" => "application/json"
    if resp.status != 200
      raise RuntimeError.new("Could not delete #{id.inspect}, http response #{resp.status}: #{resp.body}")
    end
  end

  # Send a delete all query.
  #
  # This method takes no params and will not automatically commit the deletes.
  # @example @writer.delete_all!
  def delete_all!
    delete(query: "*:*")
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

    if @thread_pool_size && @thread_pool_size > 0
      # Wait for shutdown, and time it.
      logger.debug "#{self.class.name}: Shutting down thread pool, waiting if needed..."
      elapsed = @thread_pool.shutdown_and_wait
      if elapsed > 60
        logger.warn "Waited #{elapsed} seconds for all threads, you may want to increase solr_writer.thread_pool (currently #{@settings["solr_writer.thread_pool"]})"
      end
      logger.debug "#{self.class.name}: Thread pool shutdown complete"
      logger.warn "#{self.class.name}: #{skipped_record_count} skipped records" if skipped_record_count > 0
    end

    # check again now that we've waited, there could still be some
    # that didn't show up before.
    @thread_pool.raise_collected_exception!

    # Commit if we're supposed to
    if @commit_on_close
      commit
    end
  end


  # Send a commit
  #
  # Called automatially by `close_on_commit` setting, but also can be called manually.
  #
  # If settings `solr_writer.commit_solr_update_args` is set, will be used by default.
  # That setting needs `{ commit: true }` or  `{softCommit: true}` if you want it to
  # actually do a commit!
  #
  # Optional query_params argument is the actual args to send, you must be sure
  # to make it include "commit: true" or "softCommit: true" for it to actually commit!
  # But you may want to include other params too, like optimize etc. query_param
  # argument replaces setting `solr_writer.commit_solr_update_args`, they are not merged.
  #
  # @param [Hash] query_params optional query params to send to solr update. Default {"commit" => "true"}
  #
  # @example @writer.commit
  # @example @writer.commit(softCommit: true)
  # @example @writer.commit(commit: true, optimize: true, waitFlush: false)
  def commit(query_params = nil)
    query_params ||= @commit_solr_update_args || {"commit" => "true"}
    logger.info "#{self.class.name} sending commit to solr at url #{@solr_update_url}..."

    original_timeout = @http_client.receive_timeout

    @http_client.receive_timeout = (settings["commit_timeout"] || (10 * 60)).to_i

    resp = @http_client.get(solr_update_url_with_query(query_params))
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


  # Relatively complex logic to determine if we have a valid URL and what it is,
  # and if we have basic_auth info
  #
  # Empties out user and password embedded in URI returned, to help avoid logging it.
  #
  # @returns [update_url, basic_auth_user, basic_auth_password]
  def determine_solr_update_url
    url = if settings['solr.update_url']
      check_solr_update_url(settings['solr.update_url'])
    else
      derive_solr_update_url_from_solr_url(settings['solr.url'])
    end

    parsed_uri                            = URI.parse(url)
    user_from_uri, password_from_uri      = parsed_uri.user, parsed_uri.password
    parsed_uri.user, parsed_uri.password  = nil, nil

    basic_auth_user     = @settings["solr_writer.basic_auth_user"] || user_from_uri
    basic_auth_password = @settings["solr_writer.basic_auth_password"] || password_from_uri

    return [parsed_uri.to_s, basic_auth_user, basic_auth_password]
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

  # Adapted from HTTPClient::BadResponseError.
  # It's got a #response accessor that will give you the HTTPClient
  # Response object that had a bad status, although relying on that
  # would tie you to our HTTPClient implementation that maybe should
  # be considered an implementation detail, so I dunno.
  class BadHttpResponse < RuntimeError
    # HTTP::Message:: a response
    attr_reader :response

    def initialize(msg, response = nil) # :nodoc:
      solr_error = find_solr_error(response)
      msg += ": #{solr_error}" if solr_error

      super(msg)

      @response = response
    end

    private

    # If we can get the error out of a JSON response, please do,
    # to include in error message.
    def find_solr_error(response)
      return nil unless response && response.body && response.content_type&.start_with?("application/json")

      parsed = JSON.parse(response.body)

      parsed && parsed.dig("error", "msg")
    rescue JSON::ParserError
      return nil
    end
  end

  private

  def skippable_exceptions
    @skippable_exceptions ||= (settings["solr_writer.skippable_exceptions"] || [HTTPClient::TimeoutError, SocketError, Errno::ECONNREFUSED, Traject::SolrJsonWriter::BadHttpResponse])
  end
end
