# Encoding: UTF-8

require 'test_helper'

require 'traject'
require 'traject/indexer'
require 'traject/marc4j_reader'

require 'marc'

describe "Marc4JReader" do
  it "reads Marc binary" do
    file = File.new(support_file_path("test_data.utf8.mrc"))
    settings = Traject::Indexer::Settings.new() # binary type is default
    reader = Traject::Marc4JReader.new(file, settings)

    array = reader.to_a

    assert_equal 30, array.length
    first = array.first

    assert_kind_of MARC::Record, first
    assert_equal first['245']['a'].encoding.name, "UTF-8"
  end

  it "can skip a bad subfield code" do
    file = File.new(support_file_path("bad_subfield_code.marc"))
    settings = Traject::Indexer::Settings.new() # binary type is default
    reader = Traject::Marc4JReader.new(file, settings)

    array = reader.to_a

    assert_equal 1, array.length
    assert_kind_of MARC::Record, array.first
    assert_length 2, array.first['260'].subfields
  end

  it "reads Marc binary in Marc8 encoding" do
    file = File.new(support_file_path("one-marc8.mrc"))
    settings = Traject::Indexer::Settings.new("marc4j_reader.source_encoding" => "MARC8")
    reader = Traject::Marc4JReader.new(file, settings)

    array = reader.to_a

    assert_length 1, array


    assert_kind_of MARC::Record, array.first
    a245a = array.first['245']['a']

    assert a245a.encoding.name, "UTF-8"
    assert a245a.valid_encoding?
    # marc4j converts to denormalized unicode, bah. Although
    # it's legal, it probably looks weird as a string literal
    # below, depending on your editor.
    assert_equal "Por uma outra globalização :", a245a

    # Set leader byte to proper for unicode
    assert_equal 'a', array.first.leader[9]
  end


  it "reads XML" do
    file = File.new(support_file_path "test_data.utf8.marc.xml")
    settings = Traject::Indexer::Settings.new("marc_source.type" => "xml")
    reader = Traject::Marc4JReader.new(file, settings)

    array = reader.to_a

    assert_equal 30, array.length

    first = array.first

    assert_kind_of MARC::Record, first
    assert first['245']['a'].encoding.name, "UTF-8"
    assert_equal "Fikr-i Ayāz /", first['245']['a']
  end

  it "keeps marc4j object when asked" do
    file = File.new(support_file_path "test_data.utf8.marc.xml")
    settings = Traject::Indexer::Settings.new("marc_source.type" => "xml", 'marc4j_reader.keep_marc4j' => true)
    record = Traject::Marc4JReader.new(file, settings).to_a.first
    assert_kind_of MARC::Record, record
    assert_kind_of Java::org.marc4j.marc.impl::RecordImpl, record.original_marc4j
  end

  it "replaces unicode character reference in Marc8 transcode" do
    file = File.new(support_file_path "escaped_character_reference.marc8.marc")
    # due to marc4j idiosyncracies, this test will NOT pass with default source_encoding
    # of "BESTGUESS", it only works if you explicitly set to MARC8. Doh. 
    settings = Traject::Indexer::Settings.new("marc4j_reader.source_encoding" => "MARC8") # binary type is default
    record = Traject::Marc4JReader.new(file, settings).to_a.first

    assert_equal "Rio de Janeiro escaped replacement char: \uFFFD .", record['260']['a']
  end

  describe "Marc4J Java Permissive Stream Reader" do 
    # needed for sanity check when our tests fail to see if Marc4J
    # is not behaving how we think it should. 
    it "converts character references" do
      file = File.new(support_file_path "escaped_character_reference.marc8.marc")
      reader = MarcPermissiveStreamReader.new(file.to_inputstream, true, true, "MARC-8")
      record = reader.next

      field = record.getVariableField("260")
      subfield = field.getSubfield('a'.ord)
      value = subfield.getData
      
      assert_equal "Rio de Janeiro escaped replacement char: \uFFFD .", value        
    end
  end

  it "replaces bad byte in UTF8 marc" do
    skip "Marc4J needs fixing on it's end" # Marc4J won't do this in 'permissive' mode, gah. 

    # Note this only works because the marc file DOES correctly
    # have leader byte 9 set to 'a' for UTF8, otherwise Marc4J can't do it. 
    file = File.new(support_file_path "bad_utf_byte.utf8.marc")

    settings = Traject::Indexer::Settings.new() # binary UTF8 type is default
    reader = Traject::Marc4JReader.new(file, settings)

    record = reader.to_a.first
    
    value = record['300']['a']

    assert_equal value.encoding.name, "UTF-8"
    assert value.valid_encoding?, "Has valid encoding"
    assert_equal "This is a bad byte: '\uFFFD' and another: '\uFFFD'", record['300']['a']
  end





end
