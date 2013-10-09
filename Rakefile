begin
  require 'bundler/setup'
  require "bundler/gem_tasks"
rescue LoadError
  puts "You must `gem install bundler` and `bundle install` to run rake tasks"
end

require 'rake'
require 'rake/testtask'

task :default => [:test]

Rake::TestTask.new do |t|
  if defined? JRUBY_VERSION
    t.pattern = 'test/**/*_{test,test_jruby}.rb'
  else
    t.pattern = 'test/**/*_test.rb'
  end
    
  t.libs.push 'test', 'test_support'
end

# Not documented well, but this seems to be
# the way to load rake tasks from other files
#import "lib/tasks/load_map.rake"
Dir.glob('lib/tasks/*.rake').each { |r| import r}