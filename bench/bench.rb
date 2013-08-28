$:.unshift '../lib'
require 'traject/command_line'

require 'benchmark'

filename = 'bench.mrc'

Benchmark.bmbm do |x|
  x.report("extract_marc ") do
    cmdline = Traject::CommandLine.new(["-c", "extract_marc_conf.rb", filename])
    cmdline.execute
  end
  
  x.report("extract_marc2") do
    cmdline = Traject::CommandLine.new(["-c", "extract_marc2_conf.rb", filename])
    cmdline.execute
  end
    
end

    