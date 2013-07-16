gem 'minitest' # I feel like this messes with bundler, but only way to get minitest to shut up
require 'minitest/autorun'
require 'minitest/spec'

require 'traject'
require 'marc'

def support_file_path(relative_path)
  return File.expand_path(File.join("test_support", relative_path), File.dirname(__FILE__))
end

# The 'assert' method I don't know why it's not there
def assert_length(length, obj, msg = nil)
  unless obj.respond_to? :length
    raise ArgumentError, "object with assert_length must respond_to? :length", obj
  end


  msg ||= "Expected length of #{obj} to be #{length}, but was #{obj.length}"

  assert_equal(length, obj.length, msg.to_s )
end

def assert_start_with(start_with, obj, msg = nil)
  msg ||= "expected #{obj} to start with #{start_with}"

  assert obj.start_with?(start_with), msg
end