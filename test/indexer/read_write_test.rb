require 'test_helper'

# A little Traject Writer that just keeps everything
# in an array, just added to settings for easy access
memory_writer_class = Class.new do
    def initialize(settings)
      # store them in a class variable so we can test em later
      self.class.class_variable_set(:@@last_writer_settings, (@settings = settings))
     
      @settings["memory_writer.added"] = []
    end

    def put(hash)
      @settings["memory_writer.added"] << hash
    end

    def close
      @settings["memory_writer.closed"] = true
    end
  end

describe "Traject::Indexer#process" do
  before do
    # no threading for these tests
    @indexer = Traject::Indexer.new("processing_thread_pool" => nil)
    @indexer.writer_class = memory_writer_class
    @file = File.open(support_file_path "test_data.utf8.mrc")
  end

  it "works" do
    # oops, this times_called counter isn't thread-safe under multi-threading
    # is why this fails sometimes.
    # fixed to be single-threaded for these tests.
    times_called = 0
    @indexer.to_field("title") do |record, accumulator, context|
      times_called += 1
      accumulator << "ADDED TITLE"

      assert context.index_step, "Context has #index_step set"
      assert_equal "title", context.index_step.field_name

      assert context.logger, "Context knows #logger"

      assert_equal times_called, context.position
    end

    return_value = @indexer.process( @file )

    assert return_value, "Returns `true` on success"

    # Grab the settings out of a class variable where we left em,
    # as a convenient place to store outcomes so we can test em.
    writer_settings = memory_writer_class.class_variable_get("@@last_writer_settings")

    assert writer_settings["memory_writer.added"]
    assert_equal 30, writer_settings["memory_writer.added"].length
    assert_kind_of Traject::Indexer::Context, writer_settings["memory_writer.added"].first
    assert_equal ["ADDED TITLE"], writer_settings["memory_writer.added"].first.output_hash["title"]

    # logger provided in settings
    assert writer_settings["logger"]

    assert writer_settings["memory_writer.closed"]
  end

  it "returns false if skipped records" do
    skip "Only test mock solrj writer under JRuby" unless defined? JRUBY_VERSION
    @indexer = Traject::Indexer.new(
      "solrj_writer.server_class_name" => "MockSolrServer",
      "solr.url" => "http://example.org",
      "writer_class_name" => "Traject::SolrJWriter"
    )
    @file = File.open(support_file_path "manufacturing_consent.marc")


    @indexer.to_field("id") do |record, accumulator|
      # intentionally make error
      accumulator.concat ["one_id", "two_id"]
    end
    return_value = @indexer.process(@file)

    assert ! return_value, "returns false on skipped record errors"
  end

  require 'traject/null_writer'
  it "calls after_processing after processing" do
    @indexer = Traject::Indexer.new(
      "solrj_writer.server_class_name" => "MockSolrServer",
      "solr.url" => "http://example.org",
      "writer_class_name" => "Traject::NullWriter"
    )
    @file = File.open(support_file_path "test_data.utf8.mrc")

    called = []

    @indexer.after_processing do
      called << :one
    end
    @indexer.after_processing do
      called << :two
    end

    @indexer.process(@file)

    assert_equal [:one, :two], called, "Both after_processing hooks called, in order"
  end

  describe "demo_config.rb" do
    before do
      @indexer = Traject::Indexer.new(
        "solrj_writer.server_class_name" => "MockSolrServer",
        "solr.url" => "http://example.org",
        "writer_class_name" => "Traject::NullWriter"
      )
    end

    it "parses and loads" do
      conf_path = support_file_path "demo_config.rb"
      File.open(conf_path) do |file_io|
        @indexer.instance_eval(file_io.read, conf_path)
      end
    end
  end

end
