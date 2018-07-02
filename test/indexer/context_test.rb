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


end
