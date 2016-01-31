$:.unshift File.expand_path(File.join("..", 'lib'), File.dirname(__FILE__))

require 'traject/indexer_orig'
require 'traject/indexer'
require 'benchmark/ips'

require 'marc'

marc_records = MARC::Reader.new('./batch.dat').to_a.take(10)


indexer_orig = Traject::IndexerOrig.new
indexer = Traject::Indexer.new



indexer.load_config_file('./common.rb')
indexer_orig.load_config_file('./common.rb')


puts RUBY_DESCRIPTION
Benchmark.ips do |x|
  if defined? JRUBY_VERSION
    x.warmup = 10
  else
    x.warmup = 2
  end
  
  x.time = 10

  x.report('new') do
    marc_records.each do |marc_record|
      indexer.map_record(marc_record)
    end
  end

  x.report('orig') do
    marc_records.each do |marc_record|
      indexer_orig.map_record(marc_record)
    end
  end
  

  x.compare!

end



