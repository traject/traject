require 'test_helper'

require 'traject/solrj_writer'

# It's crazy hard to test this effectively, especially under threading.
# we do our best to test decently, and keep the tests readable,
# but some things aren't quite reliable under threading, sorry.

# create's a solrj_writer, maybe with MockSolrServer, maybe
# with a real one. With settings in @settings, set or change
# in before blocks
#
# writer left in @writer, with maybe mock solr server in @mock
def create_solrj_writer
  @writer = Traject::SolrJWriter.new(@settings)

  if @settings["solrj_writer.server_class_name"] == "MockSolrServer"
    # so we can test it later
    @mock = @writer.solr_server
  end
end

def context_with(hash)
  Traject::Indexer::Context.new(:output_hash => hash)
end


# Some tests we need to run multiple ties in multiple batch/thread scenarios,
# we DRY them up by creating a method to add the tests in different describe blocks
def test_handles_errors
  it "errors but does not raise on multiple ID's" do
    @writer.put context_with("id" => ["one", "two"])
    @writer.close
    assert_equal 1, @writer.skipped_record_count, "counts skipped record"
  end

  it "errors and raises on connection error" do
    @settings.merge!("solr.url" => "http://no.such.place")
    create_solrj_writer
    assert_raises org.apache.solr.client.solrj.SolrServerException do
      @writer.put context_with("id" => ["one"])
      # in batch and/or thread scenarios, sometimes no exception raised until close
      @writer.close
    end
  end
end

# WARNING. The SolrJWriter talks to a running Solr server.
#
# set ENV['solr_url'] to run tests against a real solr server
# OR
# the tests will run against a mock SolrJ server instead.
#
#
# This is pretty limited test right now.
describe "Traject::SolrJWriter" do
  before do
    $stderr.puts "WARNING: Testing SolrJWriter with mock instance, set ENV 'solr_url' to test against real solr" unless ENV["solr_url"]

    @settings = {
      # Use XMLResponseParser just to test, and so it will work
      # with a solr 1.4 test server
      "solrj_writer.parser_class_name" => "XMLResponseParser",
      "solrj_writer.commit_on_close" => "false", # real solr is way too slow if we always have it commit on close
      "solrj_writer.batch_size" => nil
    }

    if ENV["solr_url"]
      @settings["solr.url"] = ENV["solr_url"]
    else
      @settings["solr.url"] = "http://example.org/solr"
      @settings["solrj_writer.server_class_name"] = "MockSolrServer"
    end
  end

  it "raises on missing url" do
    assert_raises(ArgumentError) { Traject::SolrJWriter.new }
    assert_raises(ArgumentError) { Traject::SolrJWriter.new("solr.url" => nil) }
  end

  it "raises on malformed URL" do
    assert_raises(ArgumentError) { Traject::SolrJWriter.new("solr.url" => "") }
    assert_raises(ArgumentError) { Traject::SolrJWriter.new("solr.url" => "adfadf") }
  end

  it "defaults to solrj_writer.batch_size more than 1" do
    assert 1 < Traject::SolrJWriter.new("solr.url" => "http://example.org/solr").settings["solrj_writer.batch_size"].to_i
  end

  describe "with no threading or batching" do
    before do
      @settings.merge!("solrj_writer.batch_size" => nil, "solrj_writer.thread_pool" => nil)
      create_solrj_writer
    end

    it "writes a simple document" do
      @writer.put context_with("title_t" => ["MY TESTING TITLE"], "id" => ["TEST_TEST_TEST_0001"])
      @writer.close


      if @mock
        assert_kind_of org.apache.solr.client.solrj.impl.XMLResponseParser, @mock.parser
        assert_equal @settings["solr.url"], @mock.url

        assert_equal 1, @mock.things_added.length
        assert_kind_of SolrInputDocument, @mock.things_added.first

        assert @mock.shutted_down
      end
    end

    it "commits on close when so set" do
      @settings.merge!("solrj_writer.commit_on_close" => "true")
      create_solrj_writer

      @writer.put context_with("title_t" => ["MY TESTING TITLE"], "id" => ["TEST_TEST_TEST_0001"])
      @writer.close

      # if it's not a mock, we don't really test anything, except that
      # no exception was raised. oh well. If it's a mock, we can
      # ask it.
      if @mock
        assert @mock.committed, "mock gets commit called on it"
      end
    end

    test_handles_errors


    # I got to see what serialized marc binary does against a real solr server,
    # sorry this is a bit out of place, but this is the class that talks to real
    # solr server right now. This test won't do much unless you have
    # real solr server set up.
    #
    # Not really a good test right now, just manually checking my solr server,
    # using this to make the add reproducible at least.
    describe "Serialized MARC" do
      it "goes to real solr somehow" do
        record = MARC::Reader.new(support_file_path  "manufacturing_consent.marc").to_a.first

        serialized = record.to_marc # straight binary
        @writer.put context_with("marc_record_t" => [serialized], "id" => ["TEST_TEST_TEST_MARC_BINARY"])
        @writer.close
      end
    end
  end

  describe "with batching but no threading" do
    before do
      @settings.merge!("solrj_writer.batch_size" => 5, "solrj_writer.thread_pool" => nil)
      create_solrj_writer
    end

    it "sends all documents" do
      docs = Array(1..17).collect do |i|
        {"id" => ["item_#{i}"], "title" => ["To be #{i} again!"]}
      end

      docs.each do |doc|
        @writer.put context_with(doc)
      end
      @writer.close

      if @mock
        # 3 batches of 5, and the leftover 2 (16, 17)
        assert_length 4, @mock.things_added

        assert_length 5, @mock.things_added[0]
        assert_length 5, @mock.things_added[1]
        assert_length 5, @mock.things_added[2]
        assert_length 2, @mock.things_added[3]
      end
    end

    test_handles_errors
  end

  describe "with batching and threading" do
    before do
      @settings.merge!("solrj_writer.batch_size" => 5, "solrj_writer.thread_pool" => 2)
      create_solrj_writer
    end

    it "sends all documents" do
      docs = Array(1..17).collect do |i|
        {"id" => ["item_#{i}"], "title" => ["To be #{i} again!"]}
      end

      docs.each do |doc|
        @writer.put context_with(doc)
      end
      @writer.close

      if @mock
        # 3 batches of 5, and the leftover 2 (16, 17)
        assert_length 4, @mock.things_added

        # we can't be sure of the order under async,
        # just three of 5 and one of 2
        assert_length 3, @mock.things_added.find_all {|array| array.length == 5}
        assert_length 1, @mock.things_added.find_all {|array| array.length == 2}
      end
    end

    test_handles_errors
  end

end

require 'thread' # Mutex
