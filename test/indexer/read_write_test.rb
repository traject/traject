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
  end

describe "Traject::Indexer#process" do 
  before do
    @indexer = Traject::Indexer.new
    @indexer.writer_class = memory_writer_class
    @file = File.open(support_file_path "test_data.utf8.mrc")
  end

  it "works" do
    @indexer.to_field("title") do |record, accumulator|
      accumulator << "ADDED TITLE"
    end

    @indexer.process( @file )

    assert @indexer.settings["memory_writer.added"]

  end


end