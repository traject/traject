require 'json'
require 'httpclient'

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
# * solr_writer.commit_on_close : true or "true" means send a commit to Solr
#   on close. We definitely encourage configuring Solr for auto commit too
# * solr_writer.commit_on_close_timeout: in Seconds, how long to be willing to wait
#   for Solr. 
class Traject::SolrJsonWriter
  attr_reader :http_client
  attr_reader :settings

  def initialize(argSettings)
    @settings = argSettings

    # A HTTPClient will re-use persistent HTTP connections, in a thread-safe
    # way -- our HTTPClient object can be safely used by multiple threads simultaneously. 
    #
    # Note HTTPClient does have an async feature, which MIGHT be one option for
    # improving performance in the future. 
    @http_client = HTTPClient.new

    logger.info("   #{self.class.name} writing to `#{settings['solr.url']}`")
    logger.info("   WARNING: #{self.class.name} is a LOW PERFORMANCE writer. For production use, traject recommends Jruby with SolrJWriter")
  end


  # Thread-safe for calling by multiple threads simultaneously on the same Writer,
  # because we do not currently batch, every individual #put call results in an 
  # individual HTTP request to Solr. We do re-use HTTP connections which should
  # provide some performance advantage. 
  def put(context)
    # Hash in an array.
    json_package = JSON.generate( [ update_hash_for_context(context) ]  )

    begin
      response = http_client.post solr_update_url, json_package, "Content-type" => "application/json" 
    rescue StandardError => exception
    end

    if exception || response.status != 200
      id            = context.source_record && context.source_record['001'] && context.source_record['001'].value
      position      = context.position
      position_str  = position ? "at file position #{position} (starting at 1)" : ""

      message = "Could not index record #{id} #{position_str}."
      message += " Solr HTTP response #{response.status} #{response.body}" if response
      message += " #{exception.class} #{exception.message}." if exception
      message += "\n"

      logger.error(message)
      logger.debug(context.source_record.to_s)
    end
  end

  # Sends a commit if so configured.
  def close
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