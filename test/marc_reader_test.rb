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


  describe "MARC binary" do
    it "reads" do
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

    it "reads Marc binary in Marc8 encoding, transcoding to UTF-8" do
      file = File.new(support_file_path("one-marc8.mrc"))
      settings = Traject::Indexer::Settings.new("marc_source.encoding" => "MARC-8")
      reader = Traject::MarcReader.new(file, settings)

      array = reader.to_a

      assert_length 1, array


      assert_kind_of MARC::Record, array.first
      a245a = array.first['245']['a']

      assert a245a.encoding.name, "UTF-8"
      assert a245a.valid_encoding?
      assert_equal "Por uma outra globalização :", a245a
    end

    it "replaces unicode character reference in Marc8 transcode" do
      file = File.new(support_file_path("escaped_character_reference.marc8.marc"))

      settings = Traject::Indexer::Settings.new("marc_source.encoding" => "MARC-8") # binary type is default
      record = Traject::MarcReader.new(file, settings).to_a.first

      assert_equal "Rio de Janeiro escaped replacement char: \uFFFD .", record['260']['a']
    end

    it "raises on unrecognized encoding for binary type" do
      file = File.new(support_file_path "one-marc8.mrc")
      settings = Traject::Indexer::Settings.new("marc_source.encoding" => "ADFADFADF")
      assert_raises(ArgumentError) do
        _record = Traject::MarcReader.new(file, settings).to_a.first
      end
    end

    it "replaces bad byte in UTF8 marc binary" do
      file = File.new(support_file_path "bad_utf_byte.utf8.marc")

      settings = Traject::Indexer::Settings.new() # binary type is default
      reader = Traject::MarcReader.new(file, settings)

      record = reader.to_a.first

      value = record['300']['a']

      assert_equal value.encoding.name, "UTF-8"
      assert value.valid_encoding?, "Has valid encoding"
      assert_equal "This is a bad byte: '\uFFFD' and another: '\uFFFD'", value
    end
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
