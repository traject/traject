require 'test_helper'

require 'traject/indexer'
require 'traject/macros/marc21'

require 'json'
require 'marc/record'

# See also marc_extractor_test.rb for more detailed tests on marc extraction,
# this is just a basic test to make sure our macro works passing through to there
# and other options.
describe "Traject::Macros::Marc21" do
  Marc21 = Traject::Macros::Marc21 # shortcut

  before do
    @indexer = Traject::Indexer.new
    @indexer.extend Traject::Macros::Marc21
    @record = MARC::Reader.new(support_file_path  "manufacturing_consent.marc").to_a.first
  end

  describe "extract_marc" do
    it "extracts marc" do
      @indexer.instance_eval do
        to_field "title", extract_marc("245ab")
      end

      output = @indexer.map_record(@record)

      assert_equal ["Manufacturing consent : the political economy of the mass media /"], output["title"]
    end

    it "respects :first=>true option" do
      @indexer.instance_eval do
        to_field "other_id", extract_marc("035a", :first => true)
      end

      output = @indexer.map_record(@record)

      assert_length 1, output["other_id"]
    end

    it "trims punctuation with :trim_punctuation => true" do
      @indexer.instance_eval do
        to_field "title", extract_marc("245ab", :trim_punctuation => true)
      end

      output = @indexer.map_record(@record)

      assert ! output["title"].first.end_with?("/"), "does not end with /"
    end

    it "Marc21::trim_punctuation class method" do
      assert_equal "one two three", Marc21.trim_punctuation("one two three")

      assert_equal "one two three", Marc21.trim_punctuation("one two three,")
      assert_equal "one two three", Marc21.trim_punctuation("one two three/")
      assert_equal "one two three", Marc21.trim_punctuation("one two three;")
      assert_equal "one two three", Marc21.trim_punctuation("one two three:")
      assert_equal "one two three .", Marc21.trim_punctuation("one two three .")
      assert_equal "one two three", Marc21.trim_punctuation("one two three.")

      assert_equal "one two [three]", Marc21.trim_punctuation("one two [three]")
      assert_equal "one two three", Marc21.trim_punctuation("one two three]")
      assert_equal "one two three", Marc21.trim_punctuation("[one two three")
      assert_equal "one two three", Marc21.trim_punctuation("[one two three]")
    end

    it "uses :translation_map" do
      @indexer.instance_eval do
        to_field "cataloging_agency", extract_marc("040a", :seperator => nil, :translation_map => "test_support/translation_maps/marc_040a_translate_test")
      end
      output = @indexer.map_record(@record)

      assert_equal ["Library of Congress"], output["cataloging_agency"]
    end
  end

  describe "serialized_marc" do
    it "serializes xml" do
      @indexer.instance_eval do
        to_field "marc_record", serialized_marc(:format => "xml")
      end
      output = @indexer.map_record(@record)

      assert_length 1, output["marc_record"]
      assert_kind_of String, output["marc_record"].first
      assert output["marc_record"].first.start_with?("<record xmlns='http://www.loc.gov/MARC21/slim'>"), "looks like serialized MarcXML"
    end

    it "serializes binary UUEncoded" do
      @indexer.instance_eval do
        to_field "marc_record", serialized_marc(:format => "binary")
      end
      output = @indexer.map_record(@record)

      assert_length 1, output["marc_record"]
      assert_kind_of String, output["marc_record"].first

      decoded = Base64.decode64( output["marc_record"].first )

      # just check the marc header for now
      assert_start_with "02067cam a2200469", decoded
    end

    it "serializes binary raw" do
      @indexer.instance_eval do
        to_field "marc_record", serialized_marc(:format => "binary", :binary_escape => false)
      end
      output = @indexer.map_record(@record)

      assert_length 1, output["marc_record"]
      assert_kind_of String, output["marc_record"].first

      # just check the marc header for now
      assert_start_with "02067cam a2200469", output["marc_record"].first
    end

    it "serializes json" do
      @indexer.instance_eval do
        to_field "marc_record", serialized_marc(:format => "json")
      end
      output = @indexer.map_record(@record)

      assert_length 1, output["marc_record"]

      # okay, let's actually deserialize it, why not

      hash = JSON.parse( output["marc_record"].first )

      deserialized = MARC::Record.new_from_hash(hash)

      assert_equal @record, deserialized
    end
  end

  it "#extract_all_marc_values" do
    @indexer.instance_eval do
      to_field "text", extract_all_marc_values
    end
    output = @indexer.map_record(@record)

    assert_length 13, output["text"]
  end


end