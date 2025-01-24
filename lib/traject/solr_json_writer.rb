require 'traject/batch_solr_json_writer_base'

# Traject::SolrJsonWriter uses the Traject::BatchSolrJsonWriterBase superclass,
# for ruby HTTPClient  client. Name of this class is generic for legacy reasons.
class Traject::SolrJsonWriter < Traject::BatchSolrJsonWriterBase

  def self.implementation_skippable_exceptions
    @implmenetation_skippable_exceptions ||= [HTTPClient::TimeoutError].freeze
  end

  def init_http_client
     @http_client = if settings["solr_json_writer.http_client"]
      settings["solr_json_writer.http_client"]
    else
      client = HTTPClient.new

      # By default we'll use teh host OS SSL certs, but you can use
      # setting solr_json_writer.use_packaged_certs to true or "true"
      # to go back to previous behavior if you have a perverse reason to.
      # https://github.com/nahi/httpclient/issues/445
      unless settings["solr_json_writer.use_packaged_certs"].to_s == "true"
        client.ssl_config.set_default_paths
      end

      if settings["solr_writer.http_timeout"]
        client.connect_timeout = client.receive_timeout = client.send_timeout = @settings["solr_writer.http_timeout"]
      end

      if @basic_auth_user || @basic_auth_password
        client.set_auth(@solr_update_url, @basic_auth_user, @basic_auth_password)
      end

      client
    end
  end


  def do_http_post(url:, body:"", headers:{}, timeout: nil)
    original_timeout = @http_client.receive_timeout
    @http_client.receive_timeout = timeout if timeout

    response = @http_client.post url, body, { "Content-type" => "application/json" }
    return HttpResponse.new(http_status: response.status, http_body: response.body, http_headers: response.headers)
  ensure
    # this handling of per-request timeout isn't actually thread-safe, we're resetting timeout
    # that will be used by other threads. But only realizing this now for this legacy
    # code, may be no way to override timeout per-request for HTTPClient?
    @http_client.receive_timeout = original_timeout if original_timeout
  end

  def implementation_specific_close
    # we don't need one in this implementation, we don't think
  end


end
