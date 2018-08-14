require 'test_helper'

describe "Traject::Indexer#process_record" do
  before do
    @writer = Traject::ArrayWriter.new
    @indexer = Traject::Indexer.new(writer: @writer) do
      to_field "record", lambda { |rec, acc| acc << rec }
    end
    @record = {key: "value"}
  end

  it "sends to writer" do
    @indexer.process_record(@record)
    assert_equal [{"record" => [@record] }], @writer.values
  end

  it "returns context" do
    context = @indexer.process_record(@record)
    assert context.is_a?(Traject::Indexer::Context)
    assert_equal @record, context.source_record
  end

  it "skips if skipped" do
    @indexer = Traject::Indexer.new(writer: @writer) do
      to_field "record", lambda { |rec, acc, context| acc << rec; context.skip! }
    end
    context = @indexer.process_record(@record)

    assert context.skip?
    assert_equal [], @writer.values
  end

  it "raises exceptions out" do
    @indexer = Traject::Indexer.new(writer: @writer) do
      to_field "record", lambda { |rec, acc, context| acc << rec; raise ArgumentError, "intentional" }
    end
    assert_raises(ArgumentError) do
      @indexer.process_record(@record)
    end
  end

  it "aliases <<" do
    assert_equal @indexer.method(:process_record), @indexer.method(:<<)

    @indexer << @record
  end

  it "raises on completed indexer" do
    @indexer.complete
    assert_raises Traject::Indexer::CompletedStateError do
      @indexer.process_record(@record)
    end
  end

end
