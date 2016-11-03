require 'test_helper'

require 'traject/indexer'
require 'traject/macros/marc21'

require 'json'
require 'marc'

# See also marc_extractor_test.rb for more detailed tests on marc extraction,
# this is just a basic test to make sure our macro works passing through to there
# and other options.
describe "Traject::Macros::Marc21" do
  Marc21 = Traject::Macros::Marc21 # shortcut

  before do
    @indexer = Traject::Indexer.new
    @record  = MARC::Reader.new(support_file_path "manufacturing_consent.marc").to_a.first
  end

  describe "extract_marc" do
    it "extracts marc" do
      @indexer.instance_eval do
        to_field "title", extract_marc("245ab")
      end

      output = @indexer.map_record(@record)

      assert_equal ["Manufacturing consent : the political economy of the mass media /"], output["title"]
      assert_equal({}, @indexer.map_record(empty_record))

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

      assert_equal ["Manufacturing consent : the political economy of the mass media"], output["title"]
      assert_equal({}, @indexer.map_record(empty_record))

    end

    it "respects :default option" do
      @indexer.instance_eval do
        to_field "only_default", extract_marc("9999", :default => "DEFAULT VALUE")
      end
      output = @indexer.map_record(@record)

      assert_equal ["DEFAULT VALUE"], output["only_default"]
    end

    it "de-duplicates by default, respects :allow_duplicates" do
      # Add a second 008
      f = @record.fields('008').first
      @record.append(f)

      @indexer.instance_eval do
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
        @indexer.instance_eval do
          to_field "foo", extract_marc("9999", :misspelled => "Who cares")
        end
      end
    end


    it "throws away nil values unless settings['allow_nil_values]'" do
      @indexer.instance_eval do
        to_field 'default_nil', extract_marc('9999', :default => nil)
      end
      output = @indexer.map_record(@record)
      assert_nil output['default_nil']
    end

    

    it "allows nil values if settings['allow_nil_values]'" do
      @indexer.settings do |s|
        s['allow_nil_values'] = true
      end
      @indexer.instance_eval do
        to_field 'default_nil', extract_marc('9999', :default => nil)
      end
      output = @indexer.map_record(@record)
      assert_equal [nil], output['default_nil']
    end


    it "Marc21::trim_punctuation class method" do
      assert_equal "one two three", Marc21.trim_punctuation("one two three")

      assert_equal "one two three", Marc21.trim_punctuation("one two three,")
      assert_equal "one two three", Marc21.trim_punctuation("one two three/")
      assert_equal "one two three", Marc21.trim_punctuation("one two three;")
      assert_equal "one two three", Marc21.trim_punctuation("one two three:")
      assert_equal "one two three .", Marc21.trim_punctuation("one two three .")
      assert_equal "one two three", Marc21.trim_punctuation("one two three.")
      assert_equal "one two three...", Marc21.trim_punctuation("one two three...")
      assert_equal "one two three", Marc21.trim_punctuation(" one two three.")

      assert_equal "one two [three]", Marc21.trim_punctuation("one two [three]")
      assert_equal "one two three", Marc21.trim_punctuation("one two three]")
      assert_equal "one two three", Marc21.trim_punctuation("[one two three")
      assert_equal "one two three", Marc21.trim_punctuation("[one two three]")

      # This one was a bug before
      assert_equal "Feminism and art", Marc21.trim_punctuation("Feminism and art.")

      assert_equal "Le réve", Marc21.trim_punctuation("Le réve.") # this assertion currently fails
    end

    it "uses :translation_map" do
      @indexer.instance_eval do
        to_field "cataloging_agency", extract_marc("040a", :separator => nil, :translation_map => "marc_040a_translate_test")
      end
      output = @indexer.map_record(@record)

      assert_equal ["Library of Congress"], output["cataloging_agency"]
    end
  end

  it "supports #extract_marc_from module method" do
    output_arr = ::Traject::Macros::Marc21.extract_marc_from(@record, "245ab", :trim_punctuation => true)
    assert_equal ["Manufacturing consent : the political economy of the mass media"], output_arr
  end

  describe "serialized_marc" do
    it "serializes xml" do
      @indexer.instance_eval do
        to_field "marc_record", serialized_marc(:format => "xml")
      end
      output = @indexer.map_record(@record)

      assert_length 1, output["marc_record"]
      assert_kind_of String, output["marc_record"].first
      roundtrip_record = MARC::XMLReader.new(StringIO.new(output["marc_record"].first)).first
      assert_equal @record, roundtrip_record
    end

    it "serializes binary UUEncoded" do
      @indexer.instance_eval do
        to_field "marc_record", serialized_marc(:format => "binary")
      end
      output = @indexer.map_record(@record)

      assert_length 1, output["marc_record"]
      assert_kind_of String, output["marc_record"].first

      decoded = Base64.decode64(output["marc_record"].first)

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

      hash = JSON.parse(output["marc_record"].first)

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
