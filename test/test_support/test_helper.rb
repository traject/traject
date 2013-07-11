require 'minitest/autorun'
require 'minitest/unit'
require 'minitest/spec'

require 'traject'
require 'marc'

def support_file_path(relative_path)
  return File.expand_path(relative_path, File.dirname(__FILE__))
end