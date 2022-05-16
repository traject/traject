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
    attr_accessor :response_status, :body, :content_type

    def initialize(*args)
      @post_args = []
      @get_args  = []
      @response_status = 200
      @mutex = Monitor.new
    end

    def post(*args)
      @mutex.synchronize do
        @post_args << args
      end

      return faked_response
    end

    def get(*args)
      @mutex.synchronize do
        @get_args << args
      end

      return faked_response
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

    private

    def faked_response
      resp = HTTP::Message.new_response(self.body || "")
      resp.status = self.response_status
      resp.content_type = self.content_type if self.content_type

      resp
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

  it "retries batch as individual records on failure" do
    @writer = create_writer("solr_writer.batch_size" => 2, "solr_writer.max_skipped" => 10)
    @fake_http_client.response_status = 500

    2.times do |i|
      @writer.put context_with({"id" => "doc_#{i}", "key" => "value"})
    end
    @writer.close

    # 1 batch, then 2 for re-trying each individually
    assert_length 3, @fake_http_client.post_args

    batch_update = @fake_http_client.post_args.first
    assert_length 2, JSON.parse(batch_update[1])

    individual_update1, individual_update2 = @fake_http_client.post_args[1], @fake_http_client.post_args[2]
    assert_length 1, JSON.parse(individual_update1[1])
    assert_length 1, JSON.parse(individual_update2[1])
  end

  it "includes Solr reported error in base error message" do
    @writer = create_writer("solr_writer.batch_size" => 1, "solr_writer.max_skipped" => 0)
    @fake_http_client.response_status = 400
    @fake_http_client.content_type = "application/json;charset=utf-8"
    @fake_http_client.body =
      { "responseHeader"=>{"status"=>400, "QTime"=>0},
        "error"=>{
          "metadata"=>["error-class", "org.apache.solr.common.SolrException", "root-error-class", "org.apache.solr.common.SolrException"],
          "msg"=>"ERROR: this is a solr error",
          "code"=>400
        }
      }.to_json

    error = assert_raises(Traject::SolrJsonWriter::MaxSkippedRecordsExceeded) {
      @writer.put context_with({"id" => "doc_1", "key" => "value"})
      @writer.close
    }
    assert_match(/ERROR: this is a solr error/, error.message)
  end

  it "can #flush" do
    2.times do |i|
      doc = {"id" => "doc_#{i}", "key" => "value"}
      @writer.put context_with(doc)
    end

    assert_length 0, @fake_http_client.post_args, "Hasn't yet written"

    @writer.flush

    assert_length 1, @fake_http_client.post_args, "Has flushed to solr"
  end

  it "defaults to not setting basic authentication" do
    settings = { "solr.url" => "http://example.com/solr/foo" }
    writer = Traject::SolrJsonWriter.new(settings)
    auth = writer.instance_variable_get("@http_client")
      .www_auth.basic_auth.instance_variable_get("@auth")
    assert(auth.empty?)
  end

  describe "HTTP basic auth" do

    it "supports basic authentication settings" do
      settings = {
        "solr.url" => "http://example.com/solr/foo",
        "solr_writer.basic_auth_user" => "foo",
        "solr_writer.basic_auth_password" => "bar",
      }

      # testing with some internal implementation of HTTPClient sorry

      writer = Traject::SolrJsonWriter.new(settings)

      auth = writer.instance_variable_get("@http_client")
        .www_auth.basic_auth.instance_variable_get("@auth")
      assert(!auth.empty?)
      assert_equal(auth.values.first, Base64.encode64("foo:bar").chomp)
    end

    it "supports basic auth from solr.url" do
      settings = {
        "solr.url" => "http://foo:bar@example.com/solr/foo",
      }

      # testing with some internal implementation of HTTPClient sorry

      writer = Traject::SolrJsonWriter.new(settings)
      auth = writer.instance_variable_get("@http_client")
        .www_auth.basic_auth.instance_variable_get("@auth")
      assert(!auth.empty?)
      assert_equal(auth.values.first, Base64.encode64("foo:bar").chomp)
    end

    it "does not log basic auth from solr.url" do
      string_io = StringIO.new
      settings = {
        "solr.url" => "http://secret_username:secret_password@example.com/solr/foo",
        "logger"   => Logger.new(string_io)
      }


      writer = Traject::SolrJsonWriter.new(settings)

      refute_includes string_io.string, "secret_username:secret_password"
      assert_includes string_io.string, "(with HTTP basic auth)"
    end
  end

  describe "commit" do
    it "commits on close when set" do
      @writer = create_writer("solr.url" => "http://example.com", "solr_writer.commit_on_close" => "true")
      @writer.put context_with({"id" => "one", "key" => ["value1", "value2"]})
      @writer.close

      last_solr_get = @fake_http_client.get_args.last

      assert_equal "http://example.com/update/json?commit=true", last_solr_get[0]
    end

    it "commits on close with commit_solr_update_args" do
      @writer = create_writer(
        "solr.url" => "http://example.com",
        "solr_writer.commit_on_close" => "true",
        "solr_writer.commit_solr_update_args" => { softCommit: true }
      )
      @writer.put context_with({"id" => "one", "key" => ["value1", "value2"]})
      @writer.close

      last_solr_get = @fake_http_client.get_args.last

      assert_equal "http://example.com/update/json?softCommit=true", last_solr_get[0]
    end

    it "can manually send commit" do
      @writer = create_writer("solr.url" => "http://example.com")
      @writer.commit

      last_solr_get = @fake_http_client.get_args.last
      assert_equal "http://example.com/update/json?commit=true", last_solr_get[0]
    end

    it "can manually send commit with specified args" do
      @writer = create_writer("solr.url" => "http://example.com", "solr_writer.commit_solr_update_args" => { softCommit: true })
      @writer.commit(commit: true, optimize: true, waitFlush: false)
      last_solr_get = @fake_http_client.get_args.last
      assert_equal "http://example.com/update/json?commit=true&optimize=true&waitFlush=false", last_solr_get[0]
    end

    it "uses commit_solr_update_args settings by default" do
      @writer = create_writer(
        "solr.url" => "http://example.com",
        "solr_writer.commit_solr_update_args" => { softCommit: true }
      )
      @writer.commit

      last_solr_get = @fake_http_client.get_args.last
      assert_equal "http://example.com/update/json?softCommit=true", last_solr_get[0]
    end

    it "overrides commit_solr_update_args with method arg" do
      @writer = create_writer(
        "solr.url" => "http://example.com",
        "solr_writer.commit_solr_update_args" => { softCommit: true, foo: "bar" }
      )
      @writer.commit(commit: true)

      last_solr_get = @fake_http_client.get_args.last
      assert_equal "http://example.com/update/json?commit=true", last_solr_get[0]
    end
  end

  describe "solr_writer.solr_update_args" do
    before do
      @writer = create_writer("solr_writer.solr_update_args" => { softCommit: true } )
    end

    it "sends update args" do
      @writer.put context_with({"id" => "one", "key" => ["value1", "value2"]})
      @writer.close

      assert_equal 1, @fake_http_client.post_args.count

      post_args = @fake_http_client.post_args.first

      assert_equal "http://example.com/solr/update/json?softCommit=true", post_args[0]
    end

    it "sends update args with delete" do
      @writer.delete("test-id")
      @writer.close

      assert_equal 1, @fake_http_client.post_args.count

      post_args = @fake_http_client.post_args.first

      assert_equal "http://example.com/solr/update/json?softCommit=true", post_args[0]
    end

    it "sends update args on individual-retry after batch failure" do
      @writer = create_writer(
        "solr_writer.batch_size" => 2,
        "solr_writer.max_skipped" => 10,
        "solr_writer.solr_update_args" => { softCommit: true }
      )
      @fake_http_client.response_status = 500

      2.times do |i|
        @writer.put context_with({"id" => "doc_#{i}", "key" => "value"})
      end
      @writer.close

      # 1 batch, then 2 for re-trying each individually
      assert_length 3, @fake_http_client.post_args

      individual_update1, individual_update2 = @fake_http_client.post_args[1], @fake_http_client.post_args[2]
      assert_equal "http://example.com/solr/update/json?softCommit=true", individual_update1[0]
      assert_equal "http://example.com/solr/update/json?softCommit=true", individual_update2[0]
    end
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
        assert_match(/ERROR.*Could not add record <output_id:doc_#{i}>: Solr error response: 500/, logged)
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

      _e = assert_raises(RuntimeError) do
        @writer.put context_with("id" => "doc_1", "key" => "value")
        @writer.close
      end
    end


    it "when catching additional skip errors, raise RuntimeError" do
      strio = StringIO.new
      @writer = create_writer(
        "solr_writer.max_skipped" => 0,
        "logger" => logger_to_strio(strio),
        "solr_writer.skippable_exceptions" => [ArgumentError]
      )
      @fake_http_client.response_status = 200
       # Stub an error to be raised
      def @fake_http_client.post(*args)
        raise ArgumentError.new('bad stuff')
      end
       _e = assert_raises(Traject::SolrJsonWriter::MaxSkippedRecordsExceeded) do
        @writer.put context_with("id" => "doc_1", "key" => "value")
        @writer.close
      end
       logged = strio.string
      assert_includes logged, 'ArgumentError: bad stuff'
    end
  end

  describe "#delete" do
    it "deletes" do
      id = "123456"
      @writer.delete(id)

      post_args = @fake_http_client.post_args.first
      assert_equal "http://example.com/solr/update/json", post_args[0]
      assert_equal JSON.generate({"delete" => id}), post_args[1]
    end

    it "raises on non-200 http response" do
      @fake_http_client.response_status = 500
      assert_raises(RuntimeError) do
        @writer.delete("12345")
      end
    end
  end

  describe "#delete_all!" do
    it "deletes all" do
      @writer.delete_all!
      post_args = @fake_http_client.post_args.first
      assert_equal "http://example.com/solr/update/json", post_args[0]
      assert_equal JSON.generate({"delete" => { "query" => "*:*"}}), post_args[1]
    end
  end
end
