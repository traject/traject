$:.unshift File.expand_path(File.join("..", 'lib'), File.dirname(__FILE__))

require 'traject/indexer'
require 'benchmark/ips'

require 'marc'

marc_records_iter = MARC::XMLReader.new('./topics.xml').take(500).enum_for(:cycle)

branch = ARGV[0]

indexer = Traject::Indexer.new
indexer.load_config_file('./common.rb')

puts RUBY_DESCRIPTION
puts "On branch #{branch}"

Benchmark.ips do |x|
  if defined? JRUBY_VERSION
    x.warmup = 10
  else
    x.warmup = 2
  end
  
  x.time = 50

  x.report(branch) do
    indexer.map_record(marc_records_iter.next)
  end
end



