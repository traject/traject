$:.unshift File.expand_path(File.join("..", 'lib'), File.dirname(__FILE__))

require 'traject/indexer_orig'
require 'traject/indexer'
require 'benchmark/ips'

require 'marc'

marc_records = MARC::Reader.new('./batch.dat').to_a


indexer_orig = Traject::IndexerOrig.new
indexer = Traject::Indexer.new



indexer.load_config_file('./common.rb')
indexer_orig.load_config_file('./common.rb')


Benchmark.ips do |x|
  x.warmup = 10
  x.time = 10

  x.report('orig') do
    marc_records.each do |marc_record|
      indexer_orig.map_record(marc_record)
    end
  end
  
  x.report('new') do
    marc_records.each do |marc_record|
      indexer.map_record(marc_record)
    end
  end




  x.compare!

end



