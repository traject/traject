require 'test_helper'

require 'traject/indexer'
require 'traject/macros/marc21'

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

end