# encoding: utf-8
require 'test_helper'

require 'traject'
require 'traject/array_writer'
require 'marc'

describe 'Simple output' do
  before do
    @reader = MARC::Reader.new(support_file_path  "test_data.utf8.mrc")
    @indexer = Traject::Indexer.new
    @indexer.instance_eval do
      to_field "id", extract_marc("001", :first => true)
      to_field "title", extract_marc("245a", :alternate_script=>false)
    end
    @writer = Traject::ArrayWriter.new(:it=>"doesn't matter")
  end
  
  it "saves the contexts" do
    @reader.each do |r|
      context = Traject::Indexer::Context.new(:source_record => r)
      @indexer.map_to_context!(context)
      @writer.put(context)
    end
    
    assert_equal 30, @writer.results.size
    assert_equal ["Fikr-i Ayāz /"], @writer.results[0].output_hash['title']
    assert_equal ["Ci an zhou bian /"], @writer.results[-1].output_hash['title']
  end
end
