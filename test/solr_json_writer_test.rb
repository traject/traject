require 'test_helper'
require 'httpclient'
require 'traject/solr_json_writer'
require 'thread'
require 'json'
require 'stringio'
require 'logger'


# Some basic tests, using a mocked HTTPClient so we can see what it did -- 
# these tests do not run against a real solr server at present. 
describe "Traject::SolrJsonWriter" do


  #######
  # A bunch of utilities to help testing
  #######

  class FakeHTTPClient
    # Always reply with this status, normally 200, can
    # be reset for testing error conditions. 
    attr_accessor :response_status
    attr_accessor :allow_update_json_path

    def initialize(*args)
      @post_args = []
      @get_args  = []
      @response_status = 200
      @allow_update_json_path = true
      @mutex = Monitor.new
    end

    def post(*args)
      @mutex.synchronize do 
        @post_args << args
      end

      resp = HTTP::Message.new_response("")
      resp.status = self.response_status

      return resp
    end

    def get (*args)
      @mutex.synchronize do
        @get_args << args
      end

      resp = HTTP::Message.new_response("")
      resp.status = self.response_status

      if args.first.end_with?("/update/json") && ! self.allow_update_json_path
        # Need to test auto-detection of /update/json being available
        resp.status = 404
      end

      return resp
    end

    def post_args
      @mutex.synchronize do
        @post_args.dup
      end
    end

    def get_args
      @mutex.synchronize do
        @get_args.dup
      end
    end

    # Everything else, just return nil please
    def method_missing(*args)
    end
  end


  def context_with(hash)
    Traject::Indexer::Context.new(:output_hash => hash)
  end

  def create_writer(settings = {})
    settings = {
      "solr.url" => "http://example.com/solr",
      "solr_json_writer.http_client" => FakeHTTPClient.new
      }.merge!(settings)
    @fake_http_client = settings["solr_json_writer.http_client"]

    writer = Traject::SolrJsonWriter.new(settings)    

    return writer
  end

  # strio = StringIO.new
  # logger_to_strio(strio)
  #
  # Later check for strio.string for contents
  def logger_to_strio(strio)
    # Yell makes this hard, let's do it with an ordinary logger, think
    # it's okay. 
    Logger.new(strio)
  end

  #########
  # Actual tests
  #########

  before do
    @writer = create_writer
  end

  it "defaults to 1 bg thread" do
    assert_equal 1, @writer.thread_pool_size
  end

  it "adds a document" do
    @writer.put context_with({"id" => "one", "key" => ["value1", "value2"]})
    @writer.close

    post_args = @fake_http_client.post_args.first

    refute_nil post_args

    assert_equal "http://example.com/solr/update/json", post_args[0]

    refute_nil post_args[1]
    posted_json = JSON.parse(post_args[1])

    assert_equal [{"id" => "one", "key" => ["value1", "value2"]}], posted_json    
  end

  it "adds more than a batch in batches" do
    (Traject::SolrJsonWriter::DEFAULT_BATCH_SIZE + 1).times do |i|
      doc = {"id" => "doc_#{i}", "key" => "value"}
      @writer.put context_with(doc)
    end
    @writer.close

    post_args = @fake_http_client.post_args

    assert_length 2, post_args, "Makes two posts to Solr for two batches"

    assert_length Traject::SolrJsonWriter::DEFAULT_BATCH_SIZE, JSON.parse(post_args[0][1]), "first batch posted with batch size docs"
    assert_length 1, JSON.parse(post_args[1][1]), "second batch posted with last remaining doc"
  end

  it "commits on close when set" do
    @writer = create_writer("solr.url" => "http://example.com", "solr_writer.commit_on_close" => "true")
    @writer.put context_with({"id" => "one", "key" => ["value1", "value2"]})
    @writer.close

    last_solr_get = @fake_http_client.get_args.last

    assert_equal "http://example.com/update/json", last_solr_get[0]
    assert_equal( {"commit" => "true"}, last_solr_get[1] )
  end

  describe "skipped records" do
    it "skips and reports under max_skipped" do
      strio = StringIO.new
      @writer = create_writer("solr_writer.max_skipped" => 10, "logger" => logger_to_strio(strio))
      @fake_http_client.response_status = 500

      10.times do |i|
        @writer.put context_with("id" => "doc_#{i}", "key" => "value")
      end
      @writer.close

      assert_equal 10, @writer.skipped_record_count

      logged = strio.string

      10.times do |i|
        assert_match /ERROR.*Could not add record doc_#{i} at source file position : Solr error response: 500/, logged
      end
    end

    it "raises when skipped more than max_skipped" do
      @writer = create_writer("solr_writer.max_skipped" => 5)
      @fake_http_client.response_status = 500

      e = assert_raises(RuntimeError) do
        6.times do |i|
          @writer.put context_with("id" => "doc_#{i}", "key" => "value")
        end
        @writer.close
      end

      assert_includes e.message, "Exceeded maximum number of skipped records"
    end

    it "raises on one skipped record when max_skipped is 0" do
      @writer = create_writer("solr_writer.max_skipped" => 0)
      @fake_http_client.response_status = 500

      e = assert_raises(RuntimeError) do
        @writer.put context_with("id" => "doc_1", "key" => "value")
        @writer.close
      end
    end
  end  

  describe "auto-discovers proper update path" do
    it "finds /update/json" do
      assert_equal "http://example.com/solr/update/json", @writer.determine_solr_update_url
    end

    it "resorts to plain /update" do 
      @fake_http_client = FakeHTTPClient.new
      @fake_http_client.allow_update_json_path = false

      @writer = create_writer("solr.url" => "http://example.com/solr", 
        "solr_json_writer.http_client" => @fake_http_client)

      assert_equal "http://example.com/solr/update", @writer.determine_solr_update_url
    end
  end


end