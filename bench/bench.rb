$:.unshift '../lib'
require 'traject/command_line'

require 'benchmark'

filename = 'bench.mrc'

config_files = %w[
  extract_marc_0_thread.rb
  extract_marc2_0_thread.rb
  extract_marc_3_thread.rb
  extract_marc2_3_thread.rb
]

puts RUBY_DESCRIPTION
Benchmark.bmbm do |x|
  config_files.each do |cf|
    x.report(cf) do
      cmdline = Traject::CommandLine.new(["-c", cf, '--log.file', 'bench.log', filename])
      cmdline.execute
    end
  end
end

    