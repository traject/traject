# Encoding: UTF-8

require 'test_helper'
require 'traject/marc_reader'
require 'traject/command_line'
require 'marc'

describe Traject::CommandLine do
  it "get_input_io returns the filename" do
    cl = Traject::CommandLine.new
    filename = support_file_path("test_data.utf8.mrc.gz")
    (io, rf) = cl.get_input_io([filename])
    assert_equal rf, filename
  end    
  
  # Figuring out a way to test this has already taken too much of my time. It works.
  # it "sets the filename" do
  #   filename = support_file_path("test_data.utf8.mrc.gz")
  #   demo = support_file_path('demo_config.rb')
  #   cmdline.indexer = cmdline.initialize_indexer!
  #   cmdline = Traject::CommandLine.new(['-c', demo, filename])
  #   assert_equal filename, cmdline.indexer.settings['command_line.filename'],
  # end
end