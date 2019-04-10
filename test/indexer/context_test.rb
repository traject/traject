require 'test_helper'

describe "Traject::Indexer::Context" do

  describe "source_record_id" do
    before do
      @record = MARC::Reader.new(support_file_path('test_data.utf8.mrc')).first
      @context = Traject::Indexer::Context.new(source_record_id_proc: Traject::Indexer::MarcIndexer.new.source_record_id_proc)
      @record_001 = "   00282214 " # from the mrc file
    end

    it "gets it from 001" do
      @context.source_record = @record
      assert_equal @record_001, @context.source_record_id
    end
  end

  describe "#record_inspect" do
    before do
      @record = MARC::Reader.new(support_file_path('test_data.utf8.mrc')).first
      @source_record_id_proc = Traject::Indexer::MarcIndexer.new.source_record_id_proc
      @record_001 = "   00282214 " # from the mrc file

      @position = 10
      @input_name = "some_file.mrc"
      @position_in_input = 10
    end

    it "can print complete inspect label" do
      @context = Traject::Indexer::Context.new(
        source_record:  @record,
        source_record_id_proc: @source_record_id_proc,
        position: @position,
        input_name: @input_name,
        position_in_input: @position_in_input
      )
      @context.output_hash["id"] = "output_id"

      assert_equal "<record ##{@position} (#{@input_name} ##{@position_in_input}), source_id:#{@record_001} output_id:output_id>", @context.record_inspect
    end
  end

  describe "#add_output" do
    before do
      @context = Traject::Indexer::Context.new
    end
    it "adds one value to nil" do
      @context.add_output(:key, "value")
      assert_equal @context.output_hash, { "key" => ["value"] }
    end

    it "adds multiple values to nil" do
      @context.add_output(:key, "value1", "value2")
      assert_equal @context.output_hash, { "key" => ["value1", "value2"] }
    end

    it "adds one value to existing accumulator" do
      @context.output_hash["key"] = ["value1"]
      @context.add_output(:key, "value2")
      assert_equal @context.output_hash, { "key" => ["value1", "value2"] }
    end

    it "uniqs by default" do
      @context.output_hash["key"] = ["value1"]
      @context.add_output(:key, "value1")
      assert_equal @context.output_hash, { "key" => ["value1"] }
    end

    it "does not unique if allow_duplicate_values" do
      @context.settings = { Traject::Indexer::ToFieldStep::ALLOW_DUPLICATE_VALUES => true }
      @context.output_hash["key"] = ["value1"]

      @context.add_output(:key, "value1")
      assert_equal @context.output_hash, { "key" => ["value1", "value1"] }
    end

    it "ignores nil values by default" do
      @context.add_output(:key, "value1", nil, "value2")
      assert_equal @context.output_hash, { "key" => ["value1", "value2"] }
    end

    it "allows nil values if allow_nil_values" do
      @context.settings = { Traject::Indexer::ToFieldStep::ALLOW_NIL_VALUES => true }

      @context.add_output(:key, "value1", nil, "value2")
      assert_equal @context.output_hash, { "key" => ["value1", nil, "value2"] }
    end

    it "ignores empty array by default" do
      @context.add_output(:key)
      @context.add_output(:key, nil)

      assert_nil @context.output_hash["key"]
    end

    it "allows empty field if allow_empty_fields" do
      @context.settings = { Traject::Indexer::ToFieldStep::ALLOW_EMPTY_FIELDS => true }

      @context.add_output(:key, nil)
      assert_equal @context.output_hash, { "key" => [] }
    end

    it "can add to multiple fields" do
      @context.add_output(["field1", "field2"], "value1", "value2")
      assert_equal @context.output_hash, { "field1" => ["value1", "value2"], "field2" => ["value1", "value2"] }
    end
  end
end
