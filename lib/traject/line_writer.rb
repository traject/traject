require 'thread'

# A writer for Traject::Indexer, that just writes out
# all the output as serialized text with #puts. 
#
# Should be thread-safe (ie, multiple worker threads can be calling #put
# concurrently), by wrapping write to actual output file in a mutex synchronize.
# This does not seem to effect performance much, as far as I could tell
# benchmarking.
#
# Output will be sent to `settings["output_file"]` string path, or else
# `settings["output_stream"]` (ruby IO object), or else stdout.
#
# This class can be sub-classed to write out different serialized
# reprentations -- subclasses will just override the #serialize
# method. For instance, see JsonWriter. 
class Traject::LineWriter
  attr_reader :settings
  attr_reader :write_mutex

  def initialize(argSettings)
    @settings     = argSettings
    @write_mutex  = Mutex.new

    # trigger lazy loading now for thread-safety
    output_file
  end


  def serialize(context)
    context.output_hash
  end    

  def put(context)
    serialized = serialize(context)
    write_mutex.synchronize do
      output_file.puts(serialized)
    end
  end

  def output_file
    unless defined? @output_file
      @output_file =
        if settings["output_file"]
          File.open(settings["output_file"], 'w:UTF-8')
        elsif settings["output_stream"]
          settings["output_stream"]
        else
          $stdout
        end
    end
    return @output_file
  end

  def close
    @output_file.close unless (@output_file.nil? || @output_file.tty?)
  end

end