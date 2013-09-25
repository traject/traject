# Encoding: UTF-8

require 'test_helper'
require 'traject/marc_reader'
require 'marc'

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

    first = array.first

    assert_kind_of MARC::Record, first

    assert first['245']['a'].encoding.name, "UTF-8"
    assert_equal "Fikr-i Ayāz /", first['245']['a']
  end

  it "reads JSON" do
    file = File.new(support_file_path "test_data.utf8.json")
    settings = Traject::Indexer::Settings.new("marc_source.type" => "json")
    reader = Traject::MarcReader.new(file, settings)
    array = reader.to_a

    assert_equal 30, array.length

    first = array.first

    assert_kind_of MARC::Record, first

    assert first['245']['a'].encoding.name, "UTF-8"
    assert_equal "Fikr-i Ayāz /", first['245']['a']
  end    



end