require 'test_helper'

# A little Traject Writer that just keeps everything
# in an array, just added to settings for easy access
memory_writer_class = Class.new do
    def initialize(settings)
      @settings = settings
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
    @indexer.to_field("title") do |record, accumulator, context|
      accumulator << "ADDED TITLE"
      assert_equal "title", context.field_name
    end

    @indexer.process( @file )

    assert @indexer.settings["memory_writer.added"]
    assert_equal 30, @indexer.settings["memory_writer.added"].length
    assert_kind_of Hash, @indexer.settings["memory_writer.added"].first
    assert_equal ["ADDED TITLE"], @indexer.settings["memory_writer.added"].first["title"]

    assert @indexer.settings["memory_writer.closed"]

  end

  


end