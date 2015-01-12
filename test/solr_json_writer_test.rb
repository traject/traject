require 'test_helper'
require 'httpclient'
require 'traject/solr_json_writer'
require 'thread'
require 'json'


# Some basic tests, using a mocked HTTPClient so we can see what it did -- 
# these tests do not run against a real solr server at present. 
describe "Traject::SolrJsonWriter" do
  class FakeHTTPClient

    def initialize(*args)
      @post_args = []
      @get_args  = []
      @mutex = Monitor.new
    end

    def post(*args)
      @mutex.synchronize do 
        @post_args << args
      end

      return HTTP::Message.new_response("")
    end

    def get (*args)
      @mutex.synchronize do
        @get_args << args
      end

      return HTTP::Message.new_response("")
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
  end


  def context_with(hash)
    Traject::Indexer::Context.new(:output_hash => hash)
  end

  def create_writer(settings = {})
    settings = {"solr.url" => "http://example.com/solr"}.merge!(settings)

    writer = Traject::SolrJsonWriter.new(settings)
    @fake_http_client = FakeHTTPClient.new
    writer.http_client = @fake_http_client

    return writer
  end

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

    assert_equal "http://example.com/solr/update", post_args[0]

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

    assert_length 2, @fake_http_client.post_args, "Makes two posts to Solr for two batches"

    # Actual order of sends may differ due to thread pool
    one_doc_add = @fake_http_client.post_args.find do |args|
      JSON.parse(args[1]).length == 1
    end
    assert one_doc_add, "Does not include a an add with one document"

    one_batch_add = @fake_http_client.post_args.find do |args|
      JSON.parse(args[1]).length == Traject::SolrJsonWriter::DEFAULT_BATCH_SIZE
    end
    assert one_batch_add, "Does not include a an add with DEFAULT_BATCH_SIZE documents"    
  end

  it "commits on close when set" do
    @writer = create_writer("solr.url" => "http://example.com", "solr_writer.commit_on_close" => "true")
    @writer.put context_with({"id" => "one", "key" => ["value1", "value2"]})
    @writer.close

    last_solr_get = @fake_http_client.get_args.last

    assert_equal "http://example.com/update", last_solr_get[0]
    assert_equal( {"commit" => "true"}, last_solr_get[1] )
  end


end