require 'test_helper'

# A little Traject Writer that just keeps everything
# in an array, just added to settings for easy access
memory_writer_class = Class.new do
    def initialize(settings)
      # store them in a class variable so we can test em later
      @@last_writer_settings = @settings = settings
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
    @indexer = Traject::Indexer.new
    @indexer.writer_class = memory_writer_class
    @file = File.open(support_file_path "test_data.utf8.mrc")
  end

  it "works" do
    times_called = 0
    @indexer.to_field("title") do |record, accumulator, context|
      times_called += 1
      accumulator << "ADDED TITLE"
      assert_equal "title", context.field_name

      assert_equal times_called, context.position
    end

    @indexer.process( @file )

    # Grab the settings out of a class variable where we left em,
    # as a convenient place to store outcomes so we can test em. 
    writer_settings = memory_writer_class.class_variable_get("@@last_writer_settings")

    assert writer_settings["memory_writer.added"]
    assert_equal 30, writer_settings["memory_writer.added"].length
    assert_kind_of Hash, writer_settings["memory_writer.added"].first
    assert_equal ["ADDED TITLE"], writer_settings["memory_writer.added"].first["title"]

    assert writer_settings["memory_writer.closed"]

  end




end