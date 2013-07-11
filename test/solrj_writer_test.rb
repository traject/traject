require 'test_helper'

require 'traject/solrj_writer'

# WARNING. The SolrJWriter talks to a running Solr server.
#
# set ENV['solrj_writer_url'] to run tests against a real solr server
# OR
# the tests will run against a mock SolrJ server instead.
#
#
# This is pretty limited test right now.
describe "Traject::SolrJWriter" do

  it "raises on missing url" do
    assert_raises(ArgumentError) { Traject::SolrJWriter.new }
    assert_raises(ArgumentError) { Traject::SolrJWriter.new("solrj_writer.url" => nil) }
  end

  describe "with a solr url" do
    before do
      @settings = {
        # Use XMLResponseParser just to test, and so it will work
        # with a solr 1.4 test server
        "solrj_writer.parser_class_name" => "XMLResponseParser",
        "solrj_writer.commit_on_close" => "true"
      }
      if ENV["solrj_writer_url"]
        @settings["solrj_writer.url"] = ENV["solrj_writer_url"]
        @writer = Traject::SolrJWriter.new(@settings)
      else
        # MOCK!!!
        $stderr.puts "WARNING: Testing SolrJWriter with mock instance"
        @settings["solrj_writer.url"] = "http://example.org/solr"
        @writer = Traject::SolrJWriter.new(@settings)
        @mock = MockSolrServer.new("http://example.org/solr")
        @writer.solr_server = @mock
      end
    end

    it "writes a simple document" do
      @writer.put "title_t" => ["MY TESTING TITLE"], "id" => ["TEST_TEST_TEST_0001"]
      @writer.close


      if @mock
        #assert_kind_of org.apache.solr.client.solrj.impl.XMLResponseParser, @mock.parser
        assert_equal @settings["solrj_writer.url"], @mock.url

        assert_equal 1, @mock.docs_added.length
        assert_kind_of SolrInputDocument, @mock.docs_added.first

        assert @mock.committed
        assert @mock.shutted_down

      else
      end
    end
  end

end

class MockSolrServer
  attr_accessor :docs_added, :url, :committed, :parser, :shutted_down

  def initialize(url)
    @url =  url
    @docs_added = []
  end

  def add(solr_input_document)
    docs_added << solr_input_document
  end

  def commit
    @committed = true
  end

  def setParser(parser)
    require 'pry'
    binding.pry 
    @parser = parser
  end

  def shutdown
    @shutted_down = true
  end

end