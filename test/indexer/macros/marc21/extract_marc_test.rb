require 'test_helper'

require 'traject/indexer'
require 'traject/macros/marc21'

require 'json'
require 'marc'


include Traject::Macros::Marc21

describe "extract_marc" do
  before do
    @indexer = Traject::Indexer.new
    @record  = MARC::Reader.new(support_file_path "manufacturing_consent.marc").to_a.first
  end


  it "extracts marc" do
    @indexer.configure do
      to_field "title", extract_marc("245ab")
    end

    output = @indexer.map_record(@record)

    assert_equal ["Manufacturing consent : the political economy of the mass media /"], output["title"]
    assert_equal({}, @indexer.map_record(empty_record))

  end

  it "respects :first=>true option" do
    @indexer.configure do
      to_field "other_id", extract_marc("035a", :first => true)
    end

    output = @indexer.map_record(@record)

    assert_length 1, output["other_id"]

  end

  it "trims punctuation with :trim_punctuation => true" do
    @indexer.configure do
      to_field "title", extract_marc("245ab", :trim_punctuation => true)
    end

    output = @indexer.map_record(@record)

    assert_equal ["Manufacturing consent : the political economy of the mass media"], output["title"]
    assert_equal({}, @indexer.map_record(empty_record))
  end

  it "can use trim_punctuation as transformation macro" do
    @indexer.configure do
      to_field "title", extract_marc("245ab"), trim_punctuation
    end

    output = @indexer.map_record(@record)

    assert_equal ["Manufacturing consent : the political economy of the mass media"], output["title"]
    assert_equal({}, @indexer.map_record(empty_record))
  end

  it "respects :default option" do
    @indexer.configure do
      to_field "only_default", extract_marc("9999", :default => "DEFAULT VALUE")
    end
    output = @indexer.map_record(@record)

    assert_equal ["DEFAULT VALUE"], output["only_default"]
  end

  it "de-duplicates by default, respects :allow_duplicates" do
    # Add a second 008
    f = @record.fields('008').first
    @record.append(f)

    @indexer.configure do
      to_field "lang1", extract_marc('008[35-37]')
      to_field "lang2", extract_marc('008[35-37]', :allow_duplicates => true)
    end

    output = @indexer.map_record(@record)
    assert_equal ["eng"], output['lang1']
    assert_equal ["eng", "eng"], output['lang2']
    assert_equal({}, @indexer.map_record(empty_record))
  end

  it "fails on an extra/misspelled argument to extract_marc" do
    assert_raises(RuntimeError) do
      @indexer.configure do
        to_field "foo", extract_marc("9999", :misspelled => "Who cares")
      end
    end
  end


  it "throws away nil values unless settings['allow_nil_values]'" do
    @indexer.configure do
      to_field 'default_nil', extract_marc('9999', :default => nil)
    end
    output = @indexer.map_record(@record)
    assert_nil output['default_nil']
  end


  it "allows nil values if settings['allow_nil_values]'" do
    @indexer.settings do |s|
      s['allow_nil_values'] = true
    end
    @indexer.configure do
      to_field 'default_nil', extract_marc('9999', :default => nil)
    end
    output = @indexer.map_record(@record)
    assert_equal [nil], output['default_nil']
  end




  it "uses :translation_map" do
    @indexer.configure do
      to_field "cataloging_agency", extract_marc("040a", :separator => nil, :translation_map => "marc_040a_translate_test")
    end
    output = @indexer.map_record(@record)

    assert_equal ["Library of Congress"], output["cataloging_agency"]
  end

  it "supports #extract_marc_from module method" do
    output_arr = ::Traject::Macros::Marc21.extract_marc_from(@record, "245ab", :trim_punctuation => true)
    assert_equal ["Manufacturing consent : the political economy of the mass media"], output_arr
  end

end
