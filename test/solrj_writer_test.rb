require 'test_helper'

require 'traject/solrj_writer'

# WARNING. The SolrJWriter talks to a running Solr server.
#
# set ENV['solr_url'] to run tests against a real solr server
# OR
# the tests will run against a mock SolrJ server instead.
#
#
# This is pretty limited test right now.
describe "Traject::SolrJWriter" do

  it "raises on missing url" do
    assert_raises(ArgumentError) { Traject::SolrJWriter.new }
    assert_raises(ArgumentError) { Traject::SolrJWriter.new("solr.url" => nil) }
  end

  it "raises on malformed URL" do
    assert_raises(ArgumentError) { Traject::SolrJWriter.new("solr.url" => "") }
    assert_raises(ArgumentError) { Traject::SolrJWriter.new("solr.url" => "adfadf") }
  end

  describe "with good setup" do
    before do
      @settings = {
        # Use XMLResponseParser just to test, and so it will work
        # with a solr 1.4 test server
        "solrj_writer.parser_class_name" => "XMLResponseParser",
        "solrj_writer.commit_on_close" => "true",

      }

      if ENV["solr_url"]
        @settings["solr.url"] = ENV["solr_url"]
      else
        $stderr.puts "WARNING: Testing SolrJWriter with mock instance"
        @settings["solr.url"] = "http://example.org/solr"
        @settings["solrj_writer.server_class_name"] = "MockSolrServer"
      end

      @writer = Traject::SolrJWriter.new(@settings)

      if @settings["solrj_writer.server_class_name"] == "MockSolrServer"
        # so we can test it later
        @mock = @writer.solr_server
      end
    end

    it "writes a simple document" do
      @writer.put "title_t" => ["MY TESTING TITLE"], "id" => ["TEST_TEST_TEST_0001"]
      @writer.close


      if @mock
        assert_kind_of org.apache.solr.client.solrj.impl.XMLResponseParser, @mock.parser
        assert_equal @settings["solr.url"], @mock.url

        assert_equal 1, @mock.things_added.length
        assert_kind_of SolrInputDocument, @mock.things_added.first

        assert @mock.committed
        assert @mock.shutted_down

      else
      end
    end

    describe "with batching of solr docs" do
      before do
        @writer.settings["solrj_writer.batch_size"] = 5
      end

      it "sends all documents" do
        docs = Array(1..17).collect do |i|
          {"id" => ["item_#{i}"], "title" => ["To be #{i} again!"]}
        end

        docs.each do |doc|
          @writer.put doc
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
    end

    describe "with SolrJ Errors" do
      it "errors but does not raise on multiple ID's" do
        @writer.put "id" => ["one", "two"]
        @writer.close
      end

      it "errors and raises on connection error" do
        @writer = Traject::SolrJWriter.new(@settings.merge "solr.url" => "http://no.such.place")
        assert_raises org.apache.solr.client.solrj.SolrServerException do
          @writer.put "id" => ["one"]
        end
      end
    end



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
        @writer.put "marc_record_t" => [serialized], "id" => ["TEST_TEST_TEST_MARC_BINARY"]
        @writer.close
      end
    end

  end

end

class MockSolrServer
  attr_accessor :things_added, :url, :committed, :parser, :shutted_down

  def initialize(url)
    @url =  url
    @things_added = []
  end

  def add(thing)
    if @url == "http://no.such.place"
      raise org.apache.solr.client.solrj.SolrServerException.new("bad uri", java.io.IOException.new)
    end

    things_added << thing
  end

  def commit
    @committed = true
  end

  def setParser(parser)
    @parser = parser
  end

  def shutdown
    @shutted_down = true
  end

end