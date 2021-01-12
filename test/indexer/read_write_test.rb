require 'test_helper'

# A little Traject Writer that just keeps everything
# in an array, just added to settings for easy access
memory_writer_class = Class.new do
    def initialize(settings)
      # store them in a class variable so we can test em later
      # Supress the warning message
      original_verbose, $VERBOSE = $VERBOSE, nil
      @settings = settings
      self.class.store_last_writer_settings(@settings)
      # Activate warning messages again.
      $VERBOSE = original_verbose
      @settings["memory_writer.added"] = []
    end

    def put(hash)
      @settings["memory_writer.added"] << hash
    end

    def close
      @settings["memory_writer.closed"] = true
    end

    private

    def self.store_last_writer_settings(settings)
      @last_writer_settings = settings
    end

    def self.last_writer_settings
      @last_writer_settings
    end
  end

describe "Traject::Indexer#process" do
  before do
    # no threading for these tests
    @indexer = Traject::Indexer::MarcIndexer.new("processing_thread_pool" => nil)
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
    writer_settings = memory_writer_class.last_writer_settings

    assert writer_settings["memory_writer.added"]
    assert_equal 30, writer_settings["memory_writer.added"].length
    assert_kind_of Traject::Indexer::Context, writer_settings["memory_writer.added"].first
    assert_equal ["ADDED TITLE"], writer_settings["memory_writer.added"].first.output_hash["title"]

    # logger provided in settings
    assert writer_settings["logger"]

    assert writer_settings["memory_writer.closed"]
  end

  require 'traject/null_writer'
  it "calls after_processing after processing" do
    @indexer = Traject::Indexer::MarcIndexer.new(
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

  it "calls after_processing from #run_after_processing_steps" do
    @indexer = Traject::Indexer.new(
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

    @indexer.run_after_processing_steps
    assert_equal [:one, :two], called, "Both after_processing hooks called, in order"
  end

  it "can't be run twice" do
    @file = File.open(support_file_path "test_data.utf8.mrc")
    @indexer = Traject::Indexer::MarcIndexer.new(
      "writer_class_name" => "Traject::NullWriter"
    )
    @indexer.process(@file)

    assert_raises Traject::Indexer::CompletedStateError do
      @indexer.process(@file)
    end
  end

  describe "demo_config.rb" do
    before do
      @indexer = Traject::Indexer.new(
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

  describe "multi stream" do
    before do
      @file2 = File.open(support_file_path "george_eliot.marc")
      @file1 = File.open(support_file_path "musical_cage.marc")
      @indexer = Traject::Indexer::MarcIndexer.new do
        self.writer_class = memory_writer_class
        to_field "title", extract_marc("245")
      end
    end

    it "parses and loads" do
      @indexer.process([@file1, @file2])
      # kinda ridic, yeah.
      output_hashes = memory_writer_class.last_writer_settings["memory_writer.added"].collect(&:output_hash)

      assert_length 2, output_hashes
      assert output_hashes.all? { |hash| hash["title"].length > 0 }
    end
  end

  describe "setting log.batch_size" do
    before do
      @indexer = Traject::Indexer::MarcIndexer.new(
        "writer_class_name" => "Traject::NullWriter",
        "log.batch_size" => 1,
      ) do
        to_field "title", extract_marc("245")
      end

      @log_output = StringIO.new
      logger = Logger.new(@log_output)
      @indexer.logger = logger

      @file = File.open(support_file_path "test_data.utf8.mrc")
    end

    it "outputs batch completion to log" do
      @indexer.process(@file)

      assert_includes @log_output.string, "Traject::Indexer#process, read 1 records at"
    end
  end
end
