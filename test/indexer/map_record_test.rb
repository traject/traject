require 'test_helper'

describe "Traject::Indexer#map_record" do 
  before do
    @indexer = Traject::Indexer.new
    @record = MARC::Reader.new(support_file_path  "manufacturing_consent.marc").to_a.first    
  end


  describe "with no indexing rules" do
    it "returns empty hash" do
      output = @indexer.map_record(@record)

      assert_kind_of Hash, output
      assert_empty output
    end
  end

  describe "#to_field" do    
    it "works with block" do
      called  = false

      @indexer.to_field("title") do |record, accumulator, context|
        assert_kind_of MARC::Record, record
        assert_kind_of Array, accumulator

        called = true # by the power of closure!
        accumulator << "Some Title"
      end
      
      output = @indexer.map_record(@record)

      assert called
      assert_kind_of Hash, output
      assert_equal ["Some Title"], output["title"]
    end

    it "works with a lambda arg" do
      called  = false

      logic = lambda do |record, accumulator, context|
        assert_kind_of MARC::Record, record
        assert_kind_of Array, accumulator

        called = true # by the power of closure!
        accumulator << "Some Title"
      end

      @indexer.to_field("title", logic) 
      
      output = @indexer.map_record(@record)

      assert called
      assert_kind_of Hash, output
      assert_equal ["Some Title"], output["title"]
    end

    it "works with both lambda and Proc" do
      block_called = false

      lambda_arg = lambda do |record, accumulator, context|
        accumulator << "Lambda-provided Value"
      end

      @indexer.to_field("title", lambda_arg) do |record, accumulator, context|
        assert_includes accumulator, "Lambda-provided Value"
        accumulator << "Block-provided Value"

        block_called = true
      end

      output = @indexer.map_record(@record)

      assert block_called
      assert_includes output["title"], "Lambda-provided Value"
      assert_includes output["title"], "Block-provided Value"
    end
  end

  describe "multiple to_field blocks" do
    it "get called in order" do
      order = []
      @indexer.to_field("title") do |rec, acc|
        order << :first_one
        acc << "First"
      end
      @indexer.to_field("title") do |rec, acc|
        order << :second_one
        acc << "Second"
      end

      output = @indexer.map_record(@record)

      assert_equal [:first_one, :second_one], order
      assert_equal ["First", "Second"], output["title"]
    end
  end

  describe "context argument" do
    it "is third argument to block" do
      called = false
      @indexer.to_field("title") do |record, accumulator, context|
        called = true

        assert_kind_of Traject::Indexer::Context, context
        
        assert_kind_of Hash, context.clipboard
        assert_kind_of Hash, context.output_hash

        assert_same record, context.source_record
        assert_same @indexer.settings, context.settings

        assert_equal 10, context.position
      end

      @indexer.map_record @record, :position => 10

      assert called
    end
  end
  
end