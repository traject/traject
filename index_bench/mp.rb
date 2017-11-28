require 'benchmark'
require 'traject'

BENCHMARKS =  Hash.new{|h, k| h[k] = Benchmark::Tms.new(0,0,0,0,0, k)}

module BenchmarkToField
  def execute(context)
    res = nil
    BENCHMARKS[field_name].add! do
      res = super(context)
    end
    res
  end
end

class Traject::Indexer::ToFieldStep
  prepend BenchmarkToField
end


settings do
  store "processing_thread_pool", 0
end


after_processing do
  File.open('benchmarks.txt', "w:utf-8") do |out|
    BENCHMARKS.each_pair {|k, x| out.puts "%6.4f %-30s" % [x.real, k]}
  end
end

      
    
