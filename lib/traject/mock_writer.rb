# A writer for Traject::Indexer, that just writes out
# all the output as serialized text with #puts. 
#
# Should be thread-safe (ie, multiple worker threads can be calling #put
# concurrently), by wrapping write to actual output file in a mutex synchronize.
# This does not seem to effect performance much, as far as I could tell
# benchmarking.
#
# Output will be sent to settings["output_file"] string path, or else
# settings["output_stream"] (ruby IO object), or else stdout.
#
# This class can be sub-classed to write out different serialized
# reprentations -- subclasses will just override the #serialize
# method. For instance, see JsonWriter. 
class Traject::MockWriter
  attr_reader :settings

  def initialize(argSettings)
  end


  def serialize(context)
    # null
  end    

  def put(context)
    # null
  end

  def close
    # null
  end

end