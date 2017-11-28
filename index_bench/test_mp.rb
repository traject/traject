$:.unshift File.expand_path(File.join("..", 'lib'), File.dirname(__FILE__))

require 'traject'
require 'traject/indexer'
require 'marc'

iter = MARC::XMLReader.new('./topics.xml').take(500).enum_for(:cycle)

indexer = Traject::Indexer.new
indexer.load_config_file('./common.rb')
indexer.load_config_file('./mp.rb')

puts RUBY_DESCRIPTION


1000.times do
  indexer.map_record(iter.next)
end






