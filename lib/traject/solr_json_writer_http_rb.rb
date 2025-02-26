require 'traject/batch_solr_json_writer_base'

# Traject::SolrJsonWriter uses the Traject::BatchSolrJsonWriterBase superclass,
# http-rb client.
#
# TODO: Has no tests. What kind of subclass-specific tests are appropriate,
#       vs tests on the superclass inherited logic that really only need
#       to be done once?
#
# NB: persistent reuqires same headers and timeout on every request:
#     https://github.com/httprb/http/discussions/733
class Traject::SolrJsonWriterHttpRb < Traject::BatchSolrJsonWriterBase

  def self.implementation_skippable_exceptions
    @implmenetation_skippable_exceptions ||= [HTTP::TimeoutError].freeze
  end

  # We're going to use mperham/connection_pool to do a POOL of connection
  def init_http_client
    timeout = settings["solr_writer.http_timeout"]

    pool_size = settings["solr_writer.thread_pool"].to_i
    # but min 1
    pool_size = 1 if pool_size == 0
    # maybe add one just to be safe?
    pool_size += 1

    @http_thread_pool = ConnectionPool.new(size: pool_size, timeout: timeout) do
      _new_http_rb_obj(timeout: timeout)
    end
  end

  def _new_http_rb_obj(timeout: nil, persistent: true)
    http_base = HTTP.headers({ "Content-type" => "application/json" })

    if timeout
      http_base = http_base.timeout(timeout)
    end

    if @basic_auth_user || @basic_auth_password
      http_base = http_base.basic_auth(:user => @basic_auth_user, :pass => @basic_auth_password)
    end

    if persistent
      http_base.persistent(@solr_update_url)
    else
      http_base
    end
  end

  def do_http_post(url:, body:"", timeout: nil)
    # we can't really handle req-specific timeouts well,
    # if we try to give a new timeout to http-rb object,
    # it won't re-use the same persistent connection, it'll create a new one.
    #
    # But that's okay I guess, superclass really only uses an explicit timeout
    # for commit-on-close
    response = if timeout
      http = _new_http_rb_obj(timeout: timeout, persistent: false)
      http.post(url, body: body).flush
    else
      @http_thread_pool.with do |http|
        http.post(url, body: body).flush
      end
    end

    Traject::BatchSolrJsonWriterBase::HttpResponse.new(
      http_status: response.code,
      http_body: response.to_s,
      http_headers: response.headers.to_h
    )
  end

  def implementation_specific_close
    @http_thread_pool.shutdown do |http|
      http.close
    end
  end
end
