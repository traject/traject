require 'test_helper'

describe "Indexer Macros#to_field" do
  before do
    @indexer = Traject::Indexer.new
    @record = MARC::Reader.new(support_file_path  "manufacturing_consent.marc").to_a.first
  end

  it "works with simple literal" do
    @indexer.configure do
      extend Traject::Macros::Basic

      to_field "source", literal("MY LIBRARY")
    end

    output = @indexer.map_record(@record)

    assert_equal ["MY LIBRARY"], output["source"]
  end

  it "works with macro AND block" do
    called = false

    @indexer.configure do
      extend Traject::Macros::Basic
      to_field "source", literal("MY LIBRARY") do |record, accumulator, context|
        called = true
        accumulator << "SECOND VALUE"
      end
    end

    output = @indexer.map_record(@record)

    assert called
    assert_equal ["MY LIBRARY", "SECOND VALUE"], output["source"]
  end



end
