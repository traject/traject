require 'uri'
require 'cgi'
require 'http'

module Traject
  # Reads an OAI feed via HTTP and feeds it directly to a traject pipeline. You don't HAVE to use
  # this to read oai-pmh, you might choose to fetch and store OAI-PMH responses to disk yourself,
  # and then process as ordinary XML.
  #
  # Example command line:
  #
  #         traject -i xml -r Traject::OaiPmhNokogiriReader -s oai_pmh.start_url="http://example.com/oai?verb=ListRecords&metadataPrefix=oai_dc" -c your_config.rb
  #
  # ## Settings
  #
  # * oai_pmh.start_url: Required, eg "http://example.com/oai?verb=ListRecords&metadataPrefix=oai_dc"
  # * oai_pmh.timeout: (default 10) timeout for http.rb in seconds
  # * oai_pmh.try_gzip: (default true). Ask server for gzip response if available
  # * oai_pmh.http_persistent: (default true). Use persistent HTTP connections.
  #
  # ## JRUBY NOTES:
  #  * Does not work with jruby 9.2 until http.rb does: https://github.com/httprb/http/issues/475
  #  * JRuby version def reads whole http response into memory before parsing; MRI version might do this too, but might not?
  #
  # ## TO DO
  #
  # This would be a lot more useful with some sort of built-in HTTP caching.
  class OaiPmhNokogiriReader
    include Enumerable

    attr_reader :settings, :input_stream

    def initialize(input_stream, settings)
      namespaces = (settings["nokogiri.namespaces"] || {}).merge(
        "oai" => "http://www.openarchives.org/OAI/2.0/"
      )


      @settings = Traject::Indexer::Settings.new(
          "nokogiri_reader.extra_xpath_hooks" => extra_xpath_hooks,
          "nokogiri.each_record_xpath" => "/oai:OAI-PMH/oai:ListRecords/oai:record",
          "nokogiri.namespaces" => namespaces
        ).with_defaults(
          "oai_pmh.timeout" => 10,
          "oai_pmh.try_gzip" => true,
          "oai_pmh.http_persistent" => true
        ).fill_in_defaults!.merge(settings)

      @input_stream = input_stream
    end

    def start_url
      settings["oai_pmh.start_url"] or raise ArgumentError.new("#{self.class.name} needs a setting 'oai_pmh.start_url'")
    end

    def start_url_verb
      @start_url_verb ||= (array = CGI.parse(URI.parse(start_url).query)["verb"]) && array.first
    end

    def extra_xpath_hooks
      @extra_xpath_hooks ||= {
        "//oai:resumptionToken" =>
          lambda do |doc, clipboard|
            token = doc.text
            if token && token != ""
              clipboard[:resumption_token] = token
            end
          end
      }
    end

    def each
      url = start_url

      resumption_token = nil
      last_resumption_token = nil
      pages_fetched = 0

      until url == nil
        resumption_token = read_and_parse_response(url) do |record|
          yield record
        end
        url = resumption_url(resumption_token)
        (last_resumption_token = resumption_token) if resumption_token
        pages_fetched += 1
      end

      logger.info("#{self.class.name}: fetched #{pages_fetched} pages; last resumptionToken found: #{last_resumption_token.inspect}")
    end

    def resumption_url(resumption_token)
      return nil if resumption_token.nil? || resumption_token == ""

      # resumption URL is just original verb with resumption token, that seems to be
      # the oai-pmh spec.
      parsed_uri = URI.parse(start_url)
      parsed_uri.query = "verb=#{CGI.escape start_url_verb}&resumptionToken=#{CGI.escape resumption_token}"
      parsed_uri.to_s
    end

    def timeout
      settings["oai_pmh.timeout"]
    end

    def logger
      @logger ||= (@settings[:logger] || Yell.new(STDERR, :level => "gt.fatal")) # null logger)
    end

    private

    # re-use an http-client for subsequent requests, to get http.rb's persistent connection re-use
    # Note this means this is NOT thread safe, which is fine for now, but we'd have to do something
    # different if we tried to multi-thread reading multiple files or something.
    #
    # @returns [HTTP::Client] from http.rb gem
    def http_client
      @http_client ||= begin
        client = nil

        if HTTP::VERSION.split(".").first.to_i > 3
          client = HTTP.timeout(timeout)
        else
          # timeout setting on http.rb 3.x are a bit of a mess.
          # https://github.com/httprb/http/issues/488
          client = HTTP.timeout(:global, write: timeout / 3, connect: timeout / 3, read: timeout / 3)
        end

        if settings["oai_pmh.try_gzip"]
          client = client.use(:auto_inflate).headers("accept-encoding" => "gzip;q=1.0, identity;q=0.5")
        end

        if settings["oai_pmh.http_persistent"]
          parsed_uri = URI.parse(start_url)
          client = client.persistent("#{parsed_uri.scheme}://#{parsed_uri.host}")
        end

        client
      end
    end

    def read_and_parse_response(url)
      http_response = http_client.get(url)

      #File.write("our_oai/#{Time.now.to_i}.xml", body)

      # Not sure why JRuby Nokogiri requires us to call #to_s on it first;
      # not sure if this has perf implications. In either case, not sure
      # if we are reading a separate copy of response into memory, or if Noko
      # consumes it streaming. Trying to explicitly stream it to nokogiri, using
      # http.rb#readpartial, just gave us a big headache.
      noko_source_arg = if Traject::Util.is_jruby?
        http_response.body.to_s
      else
        http_response.body
      end

      reader = Traject::NokogiriReader.new(noko_source_arg, settings)

      reader.each { |d| yield d }

      return reader.clipboard[:resumption_token]
    end

  end
end
