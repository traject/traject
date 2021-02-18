require 'test_helper'
require 'stringio'

require 'traject/debug_writer'
require 'traject'
require 'marc'

describe 'Simple output' do
  before do
    @record = MARC::Reader.new(support_file_path  "manufacturing_consent.marc").to_a.first
    @indexer = Traject::Indexer.new
    @indexer.configure do
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

  it "deals ok with a missing ID" do
    context      = Traject::Indexer::Context.new(:output_hash => @indexer.map_record(@record))
    logger_strio = StringIO.new
    idfield      = 'id'

    context.logger   = Logger.new(logger_strio)
    context.position = 1

    context.output_hash.delete(idfield)
    @writer.put context
    expected = [
        "record_num_1 title #{@title}",
    ]
    assert_equal expected.join("\n").gsub(/\s/, ''), @io.string.gsub(/\s/, '')
    assert_match(/At least one record \(<record #1>\) doesn't define field 'id'/, logger_strio.string)
    @writer.close

  end

  it "sets the idfield correctly" do
    bad_rec_id_field = 'iden'
    writer           = Traject::DebugWriter.new("output_stream" => @io, "debug_writer.idfield" => bad_rec_id_field)

    context = Traject::Indexer::Context.new(:output_hash => @indexer.map_record(@record))

    logger_strio = StringIO.new

    context.logger   = Logger.new(logger_strio)
    context.position = 1

    writer.put context
    expected = [
        "record_num_1 id #{@id }",
        "record_num_1 title #{@title}",
    ]
    assert_equal expected.join("\n").gsub(/\s/, ''), @io.string.gsub(/\s/, '')
    assert_match(/At least one record \(<record #1, output_id:2710183>\) doesn't define field 'iden'/, logger_strio.string)
    writer.close

  end

  it "deals ok with nil values" do
    record_with_nil_value = {"id"=>["2710183"], "title"=>["Manufacturing consent : the political economy of the mass media /"], "xyz"=>nil}
    @writer.put Traject::Indexer::Context.new(:output_hash => record_with_nil_value)
    expected = [
      "#{@id} id #{@id}",
      "#{@id} title #{@title}",
      "#{@id} xyz",
      "\n"
    ]
    assert_equal expected.join("\n").gsub(/\s/, ''), @io.string.gsub(/\s/, '')
    @writer.close

  end
end



