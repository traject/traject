require 'test_helper'

require 'traject/indexer'
require 'traject/macros/marc21'

require 'json'
require 'marc'

include Traject::Macros::Marc21


describe "The extract_all_marc_values macro" do
  before do
    @indexer = Traject::Indexer.new
    @record  = MARC::Reader.new(support_file_path "manufacturing_consent.marc").to_a.first
  end


  it "is fine with no arguments" do
    assert(extract_all_marc_values)
  end

  it "is fine with from/to strings" do
    assert(extract_all_marc_values(from: '100', to: '999'))
  end

  it "rejects from/to that aren't strings" do
    assert_raises(ArgumentError) do
      extract_all_marc_values(from: 100, to: '999')
    end
  end

  it "#extract_all_marc_values" do
    @indexer.configure do
      to_field "text", extract_all_marc_values
    end
    output = @indexer.map_record(@record)

    assert_length 13, output["text"]
  end


end







