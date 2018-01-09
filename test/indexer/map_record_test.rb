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

      @indexer.to_field("title") do |record, accumulator|
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

      logic = lambda do |record, accumulator|
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

      lambda_arg = lambda do |record, accumulator|
        accumulator << "Lambda-provided Value"
      end

      @indexer.to_field("title", lambda_arg) do |record, accumulator|
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

        assert_same @record, record
        assert_same record, context.source_record
        assert_same @indexer.settings, context.settings
      end

      @indexer.map_record @record

      assert called
    end
  end

  describe "#each_record" do
    it "is called with one-arg record" do
      called = false
      @indexer.each_record do |record|
        called = true
        assert_kind_of MARC::Record, record
      end
      @indexer.map_record(@record)

      assert called, "each_record was called"
    end
    it "is called with two-arg record and context" do
      called = false
      @indexer.each_record do |record, context|
        called = true
        assert_kind_of MARC::Record, record
        assert_kind_of Traject::Indexer::Context, context
      end
      @indexer.map_record(@record)

      assert called, "each_record was called"
    end
    it "accepts lambda AND block" do
      lambda_arg = lambda do |record, context|
        context.output_hash["field"] ||= []
        context.output_hash["field"] << "first"
      end

      @indexer.each_record(lambda_arg) do |record, context|
        context.output_hash["field"] ||= []
        context.output_hash["field"] << "second"
      end

      output = @indexer.map_record(@record)

      assert_equal %w{first second}, output["field"]
    end
    it "is called in order with #to_field" do
      @indexer.to_field("foo") {|record, accumulator| accumulator << "first"}
      @indexer.each_record {|record, context| context.output_hash["foo"] << "second" }
      @indexer.to_field("foo") {|record, accumulator| accumulator << "third"}

      output = @indexer.map_record(@record)

      assert_equal %w{first second third}, output["foo"]
    end
  end

  describe "map_to_context!" do
    before do
      @context = Traject::Indexer::Context.new(:source_record => @record, :settings => @indexer.settings, :position => 10 )
    end
    it "passes context to indexing routines"  do
      called = false
      @indexer.to_field("title") do |record, accumulator, context|
        called = true
        assert_kind_of Traject::Indexer::Context, context
        assert_same @context, context
      end

      context = @indexer.map_to_context!(@context)

      assert_same @context, context

      assert called, "Called mapping routine"
    end

    it "skips records" do

      @indexer.to_field("beforeSkip") do |rec, acc|
        acc << "Before"
      end

      @indexer.to_field('radical') do |rec, acc, context|
        context.skip!("Chomsky!") if rec['245'].to_s  =~ /Chomsky/
      end

      @indexer.to_field('afterSkip') do |rec, acc|
        raise ArgumentError, "intentional, should never happen"
      end

      output = @indexer.map_record(@record)
      assert_nil output
    end


    it "allows empty fields if settings['allow_empty_fields'" do
      @indexer.to_field('emptyfield') do |rec, acc|
        # do nothing; acc remains empty
      end
      output = @indexer.map_record(@record)
      refute_includes(output.keys, 'emptyfield', "Output contains an empty field")


      @indexer.settings do |s|
        s['allow_empty_fields'] = true
      end
      output = @indexer.map_record(@record)
      assert_equal [], output['emptyfield'], "Empty field should have been created"

    end


    it "allows nil values when appropriate" do
      @indexer.settings do |s|
        s['allow_nil_values'] = false
      end
      @indexer.to_field('nilfield') do |rec, acc|
        acc << nil
      end
      output = @indexer.map_record(@record)
      refute_includes(output.keys, 'nilfield', "Output contains a nil")

      @indexer.settings do |s|
        s['allow_nil_values'] = true
      end
      output = @indexer.map_record(@record)
      assert_includes(output.keys, 'nilfield', "Output should contain a nil")

    end

    it "allows duplicate values if they come up" do
      testval = 'just a string'
      @indexer.to_field('title') do |rec, acc|
        acc << testval
      end
      # Same things again so we get a duplicate
      @indexer.to_field('title') do |rec, acc|
        acc << testval
      end

      output = @indexer.map_record(@record)
      assert_equal [testval, testval], output['title']
    end


    it "disallows duplicate values if settings['allow_duplicate_values'] is false" do
      testval = 'just a string'
      @indexer.settings do |s|
        s['allow_duplicate_values'] = false
      end
      @indexer.to_field('title') do |rec, acc|
        acc << testval
      end
      # Same things again so we get a duplicate
      @indexer.to_field('title') do |rec, acc|
        acc << testval
      end

      output = @indexer.map_record(@record)
      assert_equal [testval], output['title']
    end

  end

end
