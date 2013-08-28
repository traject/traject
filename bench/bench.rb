$:.unshift '../lib'
require 'traject/command_line'

require 'benchmark'

filename = 'bench.mrc'

config_files = %w[
  extract_marc_conf.rb
  extract_marc2_conf.rb
]

puts RUBY_DESCRIPTION
Benchmark.bmbm do |x|
  [0, 3].each do |threads|
    config_files.each do |cf|
      x.report("#{cf} (#{threads})") do
        cmdline = Traject::CommandLine.new(["-c", cf, '-s', 'log.file=bench.log', '-s', "processing_thread_pool=#{threads}", filename])
        cmdline.execute
      end
    end
  end
end

    