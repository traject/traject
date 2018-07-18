gem 'minitest' # I feel like this messes with bundler, but only way to get minitest to shut up
require 'minitest/autorun'
require 'minitest/spec'

require 'webmock/minitest'

require 'traject'
require 'marc'

# keeps things from complaining about "yell-1.4.0/lib/yell/adapters/io.rb:66 warning: syswrite for buffered IO"
# for reasons I don't entirely understand, involving yell using syswrite and tests sometimes
# using $stderr.puts. https://github.com/TwP/logging/issues/31
STDERR.sync = true

# Hacky way to turn off Indexer logging by default, say only
# log things higher than fatal, which is nothing.
Traject::Indexer.singleton_class.prepend(Module.new do
  def default_settings
    super.merge("log.level" => "gt.fatal")
  end
end)


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


# An empty record, for making sure extractors and macros work when
# the fields they're looking for aren't there

def empty_record
  rec = MARC::Record.new
  rec.append(MARC::ControlField.new('001', '000000000'))
  rec
end

# pretends to be a Solr HTTPServer-like thing, just kind of mocks it up
# and records what happens and simulates errors in some cases.
class MockSolrServer
  class Exception < RuntimeError;end

  attr_accessor :things_added, :url, :committed, :parser, :shutted_down

  def initialize(url)
    @url =  url
    @things_added = []
    @add_mutex = Mutex.new
  end

  def add(thing)
    @add_mutex.synchronize do # easy peasy threadsafety for our mock
      if @url == "http://no.such.place"
        raise MockSolrServer::Exception.new("mock bad uri")
      end

      # simulate a multiple id error please
      if [thing].flatten.find {|doc| doc.getField("id").getValueCount() != 1}
        raise MockSolrServer::Exception.new("mock non-1 size of 'id'")
      else
        things_added << thing
      end
    end
  end

  def commit
    @committed = true
  end

  def setParser(parser)
    @parser = parser
  end

  def shutdown
    @shutted_down = true
  end

end
