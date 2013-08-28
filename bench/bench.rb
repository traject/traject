#!/usr/bin/env jruby

$:.unshift '../lib'
require 'traject/command_line'

require 'benchmark'

unless ARGV.size >= 2
  STDERR.puts "\n     Benchmark two (or more) different config files with both 0 and 3 threads against the given marc file\n"
  STDERR.puts "\n     Usage:"
  STDERR.puts "         jruby --server bench.rb config1.rb config2.rb [...configN.rb] filename.mrc\n\n"
  exit
end

filename = ARGV.pop
config_files = ARGV

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

    