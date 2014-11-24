require 'json'
require 'httpclient'
require 'thread' # for Queue

# Writes to a Solr using Solr's JSON update handler:
# https://wiki.apache.org/solr/UpdateJSON
# Requires Solr 3.2+
#
# NOTE: This is a LOW PERFORMANCE writer, designed for convenience under MRI. 
# For production use, we strongly recommend Jruby and the SolrJWriter. 
#
# ## Settings Used
#
# * solr.url: Path to your solr server
# * "solr.update_batch_size" 
# * solr_writer.commit_on_close : true or "true" means send a commit to Solr
#   on close. We definitely encourage configuring Solr for auto commit too
# * solr_writer.commit_on_close_timeout: in Seconds, how long to be willing to wait
#   for Solr. 
#
# TODO: Quit fatally after more than X individual doc add errors, so we don't go on
# for hours when it ain't working. Requires a thread-safe variable, make our own
# with a mutex, or use one from concurrent-ruby if we add that. 
class Traject::SolrJsonWriter
  DefaultBatchSize = 200

  attr_reader :http_client, :batch_queue
  attr_reader :settings

  def initialize(argSettings)
    @settings = argSettings
    @settings["solr.update_batch_size"] ||= DefaultBatchSize

    # A HTTPClient will re-use persistent HTTP connections, in a thread-safe
    # way -- our HTTPClient object can be safely used by multiple threads simultaneously. 
    @http_client = HTTPClient.new

    @batch_queue = Queue.new

    @debug_ascii_progress = (@settings["debug_ascii_progress"].to_s == "true")

    logger.info("   #{self.class.name} writing to `#{settings['solr.url']}` with batch size #{batch_size}")
    logger.info("   WARNING: #{self.class.name} is a LOW PERFORMANCE writer. For production use, traject recommends Jruby with SolrJWriter")
  end


  # Thread-safe for calling by multiple threads simultaneously on the same Writer,
  # because we do not currently batch, every individual #put call results in an 
  # individual HTTP request to Solr. We do re-use HTTP connections which should
  # provide some performance advantage. 
  def put(context)
    if batch_size <= 1
      send_single_context_to_solr(context)
    else
      batch_queue << context

      queue_size = batch_queue.size()
      if queue_size >= batch_size
        $stderr.write("^") if @debug_ascii_progress
        send_batch_to_solr pull_from_queue(batch_queue, queue_size)
      end
    end
  end  


  # Takes an array of contexts, sends them to solr. If there's an error,
  # prints out a warning and retries each individually with
  # send_single_context_to_solr (the latter will write an error on each
  # failed record if any continue to fail)
  def send_batch_to_solr(context_array)
    response, exception = send_to_solr(context_array)

    $stderr.write("%") if @debug_ascii_progress

    if exception || response.status != 200 
      message = "Error encountered in batch solr add, will re-try documents individually, at a performance penalty...\n"
      message += " Solr HTTP response #{response.status} #{response.body}" if response
      message += Traject::Util.exception_to_log_message(e) if exception
      message += "\n"
      logger.warn message

      context_array.each do |context|
        send_single_context_to_solr context
      end
    end
  end

  # Takes a single Traject::Indexer::Context, 
  # will output error logging on failure to save. 
  #
  # returns true or false, true means success. 
  def send_single_context_to_solr(context)
    response, exception = send_to_solr([context])

    if exception || response.status != 200       
      id            = context.source_record && context.source_record['001'] && context.source_record['001'].value
      position      = context.position
      position_str  = position ? "at file position #{position} (starting at 1)" : ""

      message = "Could not index record #{id} #{position_str}."
      message += " Solr HTTP response #{response.status} #{response.body}" if response
      message += Traject::Util.exception_to_log_message(e) if exception
      message += ".\n"

      logger.error(message)
      logger.debug(context.source_record.to_s)

      return false
    end

    return true
  end

  # Takes an array of Traject::Indexer::Context objects, sends them
  # all to Solr. 
  #
  # returns an [http_response, exception] pair, where either may
  # be nil in some error cases. Check excpeption non-nil or 
  # http_response.status != 200 for error. 
  def send_to_solr(array_of_contexts)
    json_package = JSON.generate(  array_of_contexts.collect {|c| update_hash_for_context(c)} )

    begin
      response = http_client.post solr_update_url, json_package, "Content-type" => "application/json" 
    rescue StandardError => exception
    end

    return [response, exception]
  end

  # Sends a commit if so configured.
  def close
    # Any leftovers in batch buffer? Send em to the threadpool too.
    if batch_queue.size > 0
      $stderr.write("^") if @debug_ascii_progress

      send_batch_to_solr pull_from_queue(batch_queue)      
    end

    if settings["solr_writer.commit_on_close"].to_s == "true"
      commit_url = settings["solr.url"].chomp("/") + "/update?commit=true"
      logger.info "SolrJsonWriter: Sending commit at GET #{commit_url}" 
      
      if settings["solr_writer.commit_on_close_timeout"]
        # set the httpclient timeouts, don't worry about resetting it
        # when we're done, we're about to close. 
        http_client.receive_timeout = settings["solr_writer.commit_on_close_timeout"].to_f
      end

      response = http_client.get commit_url
      if response.status != 200
        logger.error("Error sending commit to Solr: #{response.status} #{response.body}")
      end
    end
  end

  def logger
    settings["logger"] ||=  Yell.new(STDERR, :level => "gt.fatal") # null logger
  end

  def batch_size
    @batch_size ||= settings["solr.update_batch_size"].to_i
  end

  def pull_from_queue(queue, number = nil)
    number ||= queue.size

    result = []

    number.times do 
      break if queue.empty?
      result << queue.deq
    end

    return result
  end



  # Returns a hash suitable for including in Json to represent a single document
  # update
  def update_hash_for_context(context)
    # Just the output hash. Do we need to make single-values strings instead
    # of arrays?
    return context.output_hash
  end

  # In Solr 4.0, we can use plain /update with a JSON content-type. Previously
  # we need to send to /update/json. We trust the `solr.version` setting to determine
  def solr_update_url
    settings["solr.url"].chomp("/") + if settings["solr.version"] && settings['solr.version'].split('.').first.to_i < 4
      "/update/json"
    else
      "/update"
    end
  end


  protected 

end