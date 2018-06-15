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

    it "gets it from the id" do
      @context.output_hash['id'] = 'the_record_id'
      assert_equal 'the_record_id', @context.source_record_id
    end

    it "gets from the id with non-MARC source" do
      @context.source_record = Object.new
      @context.output_hash['id'] = 'the_record_id'
      assert_equal 'the_record_id', @context.source_record_id
    end

    it "gets it from both 001 and id" do
      @context.output_hash['id'] = 'the_record_id'
      @context.source_record = @record
      assert_equal [@record_001, 'the_record_id'].join('/'), @context.source_record_id
    end
  end

end
