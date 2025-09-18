require 'test_helper'
require 'httpx'
require 'traject/solr_json_writer2'
require 'thread'
require 'json'
require 'stringio'
require 'logger'


require "httpx/adapters/webmock"
WebMock.enable! # not sure why we need this


# Some basic tests, using a mocked http client so we can see what it did --
# these tests do not run against a real solr server at present.
describe "Traject::SolrJsonWriter2" do
  TEST_SOLR_URL = "http://example.com/solr"

  #######
  # utilities to help testing
  #######

  def context_with(hash)
    Traject::Indexer::Context.new(:output_hash => hash)
  end

  def create_writer(settings = {})
    settings = {
      "solr.url" => TEST_SOLR_URL,
      }.merge!(settings)

    Traject::SolrJsonWriter2.new(settings)
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
    stub_request(:post, "#{TEST_SOLR_URL}/update/json").to_return(status: 200)

    @writer.put context_with({"id" => "one", "key" => ["value1", "value2"]})
    @writer.close

    assert_requested :post, "#{TEST_SOLR_URL}/update/json" do |request|
      posted_json = JSON.parse(request.body)
      assert_equal [{"id" => "one", "key" => ["value1", "value2"]}], posted_json
    end
  end

  it "adds more than a batch in batches" do
    stub_request(:post, "#{TEST_SOLR_URL}/update/json").to_return(status: 200)

    (Traject::SolrJsonWriter2::DEFAULT_BATCH_SIZE + 1).times do |i|
      doc = {"id" => "doc_#{i}", "key" => "value"}
      @writer.put context_with(doc)
    end
    @writer.close

    assert_requested(:post, "#{TEST_SOLR_URL}/update/json", times: 2)

    # first batch with 100
    assert_requested(:post, "#{TEST_SOLR_URL}/update/json") do |request|
      posted_json = JSON.parse(request.body)
      posted_json.length == Traject::SolrJsonWriter2::DEFAULT_BATCH_SIZE
    end

    # second batch with just one
    assert_requested(:post, "#{TEST_SOLR_URL}/update/json") do |request|
      posted_json = JSON.parse(request.body)
      posted_json.length == 1
    end
  end

  it "retries batch as individual records on failure" do
    # capture post bodies for easier testing
    post_bodies = []
    stub_request(:post, "#{TEST_SOLR_URL}/update/json").with { |request|
      post_bodies << JSON.parse(request.body)
      true
    }.to_return(status: 500)

    @writer = create_writer("solr_writer.batch_size" => 2, "solr_writer.max_skipped" => 10)

    2.times do |i|
      @writer.put context_with({"id" => "doc_#{i}", "key" => "value"})
    end
    @writer.close

    # 1 batch, then 2 for re-trying each individually
    assert_requested(:post, "#{TEST_SOLR_URL}/update/json", times: 3)

    batch_update = post_bodies.first

    assert_length 2, batch_update

    individual_update1, individual_update2 = post_bodies[1], post_bodies[2]
    assert_length 1, individual_update1
    assert_length 1, individual_update2
  end

  it "includes Solr reported error in base error message" do
    stub_request(:post, "#{TEST_SOLR_URL}/update/json").
      to_return(
        status: 400,
        headers: { content_type: "application/json;charset=utf-8" },
        body: { "responseHeader"=>{"status"=>400, "QTime"=>0},
                "error"=>{
                  "metadata"=>["error-class", "org.apache.solr.common.SolrException", "root-error-class", "org.apache.solr.common.SolrException"],
                  "msg"=>"ERROR: this is a solr error",
                  "code"=>400
                }
              }.to_json
      )


    @writer = create_writer("solr_writer.batch_size" => 1, "solr_writer.max_skipped" => 0)

    error = assert_raises(Traject::SolrJsonWriter2::MaxSkippedRecordsExceeded) {
      @writer.put context_with({"id" => "doc_1", "key" => "value"})
      @writer.close
    }
    assert_match(/ERROR: this is a solr error/, error.message)
  end

  it "can #flush" do
    stub_request(:post, "#{TEST_SOLR_URL}/update/json")

    2.times do |i|
      doc = {"id" => "doc_#{i}", "key" => "value"}
      @writer.put context_with(doc)
    end

    # Hasn't yet written
    assert_not_requested(:post, "#{TEST_SOLR_URL}/update/json")

    @writer.flush

    # Has flushed to solr
    assert_requested(:post, "#{TEST_SOLR_URL}/update/json")
  end

  it "defaults to not setting basic authentication" do
    settings = { "solr.url" => "http://example.com/solr/foo" }
    writer = Traject::SolrJsonWriter2.new(settings)

    headers = writer.instance_variable_get("@http_client")
      .send(:default_options).headers.to_h
    assert(headers.empty?)
  end

  describe "HTTP basic auth" do

    it "supports basic authentication settings" do
      settings = {
        "solr.url" => "http://example.com/solr/foo",
        "solr_writer.basic_auth_user" => "foo",
        "solr_writer.basic_auth_password" => "bar",
      }

      # testing with some internal implementation of HTTPClient sorry

      writer = Traject::SolrJsonWriter2.new(settings)
      headers = writer.instance_variable_get("@http_client")
        .send(:default_options).headers.to_h
      assert(!headers.empty?)
      assert_equal(headers['authorization']&.split(' ')&.last, Base64.encode64("foo:bar").chomp)
    end

    it "supports basic auth from solr.url" do
      settings = {
        "solr.url" => "http://foo:bar@example.com/solr/foo",
      }

      # testing with some internal implementation of HTTPClient sorry

      writer = Traject::SolrJsonWriter2.new(settings)
      headers = writer.instance_variable_get("@http_client")
        .send(:default_options).headers.to_h

      assert(!headers.empty?)
      assert_equal(headers['authorization']&.split(' ')&.last, Base64.encode64("foo:bar").chomp)
    end

    it "does not log basic auth from solr.url" do
      string_io = StringIO.new
      settings = {
        "solr.url" => "http://secret_username:secret_password@example.com/solr/foo",
        "logger"   => Logger.new(string_io)
      }


      writer = Traject::SolrJsonWriter2.new(settings)

      refute_includes string_io.string, "secret_username:secret_password"
      assert_includes string_io.string, "(with HTTP basic auth)"
    end
  end

  describe "commit" do
    it "commits on close when set" do
      stub_request(:post, "#{TEST_SOLR_URL}/update/json")
      stub_request(:get, "#{TEST_SOLR_URL}/update/json?commit=true")

      @writer = create_writer("solr.url" => TEST_SOLR_URL, "solr_writer.commit_on_close" => "true")
      @writer.put context_with({"id" => "one", "key" => ["value1", "value2"]})
      @writer.close

      assert_requested(:get, "#{TEST_SOLR_URL}/update/json?commit=true")
    end

    it "commits on close with commit_solr_update_args" do
      stub_request(:post, "#{TEST_SOLR_URL}/update/json")
      stub_request(:get, "#{TEST_SOLR_URL}/update/json?softCommit=true")

      @writer = create_writer(
        "solr.url" => TEST_SOLR_URL,
        "solr_writer.commit_on_close" => "true",
        "solr_writer.commit_solr_update_args" => { softCommit: true }
      )
      @writer.put context_with({"id" => "one", "key" => ["value1", "value2"]})
      @writer.close

      assert_requested(:get, "#{TEST_SOLR_URL}/update/json?softCommit=true")
    end

    it "can manually send commit" do
      stub_request(:get, "#{TEST_SOLR_URL}/update/json?commit=true")

      @writer = create_writer("solr.url" => TEST_SOLR_URL)
      @writer.commit

      assert_requested(:get, "#{TEST_SOLR_URL}/update/json?commit=true")
    end

    it "can manually send commit with specified args" do
      stub_request(:get, "#{TEST_SOLR_URL}/update/json?commit=true&optimize=true&waitFlush=false")

      @writer = create_writer("solr.url" => TEST_SOLR_URL, "solr_writer.commit_solr_update_args" => { softCommit: true })
      @writer.commit(commit: true, optimize: true, waitFlush: false)

      assert_requested(:get, "#{TEST_SOLR_URL}/update/json?commit=true&optimize=true&waitFlush=false")
    end

    it "uses commit_solr_update_args settings by default" do
      stub_request(:get, "#{TEST_SOLR_URL}/update/json?softCommit=true")

      @writer = create_writer(
        "solr.url" => TEST_SOLR_URL,
        "solr_writer.commit_solr_update_args" => { softCommit: true }
      )
      @writer.commit

      assert_requested(:get, "#{TEST_SOLR_URL}/update/json?softCommit=true")
    end

    it "overrides commit_solr_update_args with method arg" do
      stub_request(:get, "#{TEST_SOLR_URL}/update/json?commit=true")

      @writer = create_writer(
        "solr.url" => TEST_SOLR_URL,
        "solr_writer.commit_solr_update_args" => { softCommit: true, foo: "bar" }
      )
      @writer.commit(commit: true)

      assert_requested(:get, "#{TEST_SOLR_URL}/update/json?commit=true")
    end
  end

  describe "solr_writer.solr_update_args" do
    before do
      @writer = create_writer("solr_writer.solr_update_args" => { softCommit: true } )
    end

    it "sends update args" do
      stub_request(:post, "#{TEST_SOLR_URL}/update/json?softCommit=true")

      @writer.put context_with({"id" => "one", "key" => ["value1", "value2"]})
      @writer.close

      assert_requested(:post, "#{TEST_SOLR_URL}/update/json?softCommit=true")
    end

    it "sends update args with delete" do
      stub_request(:post, "#{TEST_SOLR_URL}/update/json?softCommit=true")

      @writer.delete("test-id")
      @writer.close

      assert_requested(:post, "#{TEST_SOLR_URL}/update/json?softCommit=true", times: 1)
    end

    it "sends update args on individual-retry after batch failure" do
      stub_request(:post, "#{TEST_SOLR_URL}/update/json?softCommit=true").to_return(status: 500)

      @writer = create_writer(
        "solr_writer.batch_size" => 2,
        "solr_writer.max_skipped" => 10,
        "solr_writer.solr_update_args" => { softCommit: true }
      )

      2.times do |i|
        @writer.put context_with({"id" => "doc_#{i}", "key" => "value"})
      end
      @writer.close

      # 1 batch, then 2 for re-trying each individually
      assert_requested(:post, "#{TEST_SOLR_URL}/update/json?softCommit=true", times: 3)
    end
  end

  describe "skipped records" do
    it "skips and reports under max_skipped" do
      stub_request(:post, "#{TEST_SOLR_URL}/update/json").to_return(status: 500)

      strio = StringIO.new
      @writer = create_writer("solr_writer.max_skipped" => 10, "logger" => logger_to_strio(strio))

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
      stub_request(:post, "#{TEST_SOLR_URL}/update/json").to_return(status: 500)

      @writer = create_writer("solr_writer.max_skipped" => 5)

      e = assert_raises(RuntimeError) do
        6.times do |i|
          @writer.put context_with("id" => "doc_#{i}", "key" => "value")
        end
        @writer.close
      end

      assert_includes e.message, "Exceeded maximum number of skipped records"
    end

    it "raises on one skipped record when max_skipped is 0" do
      stub_request(:post, "#{TEST_SOLR_URL}/update/json").to_return(status: 500)

      @writer = create_writer("solr_writer.max_skipped" => 0)

      _e = assert_raises(RuntimeError) do
        @writer.put context_with("id" => "doc_1", "key" => "value")
        @writer.close
      end
    end


    it "when catching additional skip errors, raise RuntimeError" do
      stub_request(:post, "#{TEST_SOLR_URL}/update/json").to_raise(ArgumentError.new('bad stuff'))

      strio = StringIO.new
      @writer = create_writer(
        "solr_writer.max_skipped" => 0,
        "logger" => logger_to_strio(strio),
        "solr_writer.skippable_exceptions" => [ArgumentError]
      )

       _e = assert_raises(Traject::SolrJsonWriter2::MaxSkippedRecordsExceeded) do
        @writer.put context_with("id" => "doc_1", "key" => "value")
        @writer.close
      end
       logged = strio.string
      assert_includes logged, 'ArgumentError: bad stuff'
    end
  end

  describe "#delete" do
    it "deletes" do
      stub_request(:post, "#{TEST_SOLR_URL}/update/json")

      id = "123456"
      @writer.delete(id)

      assert_requested(:post, "#{TEST_SOLR_URL}/update/json", body: JSON.generate({"delete" => id}))
    end

    it "raises on non-200 http response" do
      stub_request(:post, "#{TEST_SOLR_URL}/update/json").to_return(status: 500)

      assert_raises(RuntimeError) do
        @writer.delete("12345")
      end
    end
  end

  describe "#delete_all!" do
    it "deletes all" do
      stub_request(:post, "#{TEST_SOLR_URL}/update/json")

      @writer.delete_all!

      assert_requested(:post, "#{TEST_SOLR_URL}/update/json", body: JSON.generate({"delete" => { "query" => "*:*"}}))
    end
  end
end
