require 'test_helper'

require 'traject/indexer'
require 'traject/macros/marc21'
require 'json'
require 'marc'

include Traject::Macros::Marc21


describe "serialized_marc" do
  before do
    @indexer = Traject::Indexer.new
    @record  = MARC::Reader.new(support_file_path "manufacturing_consent.marc").to_a.first
  end

  it "serializes xml" do
    @indexer.configure do
      to_field "marc_record", serialized_marc(:format => "xml")
    end
    output = @indexer.map_record(@record)

    assert_length 1, output["marc_record"]
    assert_kind_of String, output["marc_record"].first
    roundtrip_record = MARC::XMLReader.new(StringIO.new(output["marc_record"].first)).first
    assert_equal @record, roundtrip_record
  end

  it "serializes binary UUEncoded" do
    @indexer.configure do
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
    @indexer.configure do
      to_field "marc_record", serialized_marc(:format => "binary", :binary_escape => false)
    end
    output = @indexer.map_record(@record)

    assert_length 1, output["marc_record"]
    assert_kind_of String, output["marc_record"].first

    # just check the marc header for now
    assert_start_with "02067cam a2200469", output["marc_record"].first
  end

  it "serializes json" do
    @indexer.configure do
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
