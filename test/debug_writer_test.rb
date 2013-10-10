require 'test_helper'
require 'stringio'

require 'traject/debug_writer'
require 'traject'
require 'marc'

describe 'Simple output' do
  before do
    @record = MARC::Reader.new(support_file_path  "manufacturing_consent.marc").to_a.first
    @indexer = Traject::Indexer.new
    @indexer.instance_eval do
      to_field "id", extract_marc("001", :first => true)
      to_field "title", extract_marc("245ab")
    end
    @io = StringIO.new
    @writer = Traject::DebugWriter.new("output_stream" => @io)

    @id = "2710183"
    @title = "Manufacturing consent : the political economy of the mass media /"
  end

  it "does a simple output" do
    @writer.put Traject::Indexer::Context.new(:output_hash => @indexer.map_record(@record))
    expected = [
      "#{@id} id #{@id}",
      "#{@id} title #{@title}",
      "\n"
    ]
    assert_equal expected.join("\n").gsub(/\s/, ''), @io.string.gsub(/\s/, '')
    @writer.close

  end

end



