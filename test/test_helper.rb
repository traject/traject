gem 'minitest' # I feel like this messes with bundler, but only way to get minitest to shut up
require 'minitest/autorun'
require 'minitest/spec'

require 'traject'
require 'marc'

def support_file_path(relative_path)
  return File.expand_path(File.join("test_support", relative_path), File.dirname(__FILE__))
end
