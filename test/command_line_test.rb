# Encoding: UTF-8

require 'test_helper'
require 'traject/marc_reader'
require 'traject/command_line'
require 'marc'

describe Traject::CommandLine do
  it "stores the filename" do
    cl = Traject::CommandLine.new
    cl.indexer = Traject::Indexer.new({})
    filename = support_file_path("test_data.utf8.mrc.gz")
    file = cl.get_input_io(cl.indexer, [filename])
    assert_equal cl.indexer.settings['command_line.filename'], filename
  end    
end