# Encoding: UTF-8

require 'test_helper'
require 'traject/macros/marc21'

include Traject::Macros::Marc21

describe "The extract_all_marc_values macro" do

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
end
