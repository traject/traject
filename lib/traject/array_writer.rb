# A Null writer that just takes the contexts offered it and stuffs them into
# an array, which can be accessed via writer#results
#
# Useful for nothing but debugging.

require 'jruby/synchronized'
require 'traject/mock_writer'

class Traject::ArrayWriter < Traject::MockWriter
  
  attr_reader :results
  def initialize(argSettings)
    @results = SafeArray.new
  end
  
  def put(context)
    @results << context
  end
  
  # Get a threadsafe array to push things onto
  class SafeArray < Array
    include JRuby::Synchronized
  end
  
  
end