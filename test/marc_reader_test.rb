require 'test_helper'
require 'traject/marc_reader'

describe "Traject::MarcReader" do


  it "reads XML" do
    file = File.new(support_file_path "test_data.utf8.marc.xml")
    settings = Traject::Indexer::Settings.new("marc_source.type" => "xml")
    reader = Traject::MarcReader.new(file, settings)

    array = reader.to_a

    assert_equal 30, array.length
  end

  it "reads Marc binary" do
    file = File.new(support_file_path "test_data.utf8.mrc")
    settings = Traject::Indexer::Settings.new() # binary type is default
    reader = Traject::MarcReader.new(file, settings)

    array = reader.to_a

    assert_equal 30, array.length
  end



end