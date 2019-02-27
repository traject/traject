require 'thread'

# A writer for Traject::Indexer, that just writes out
# all the output as serialized text with #puts.
#
# Should be thread-safe (ie, multiple worker threads can be calling #put
# concurrently), by wrapping write to actual output file in a mutex synchronize.
# This does not seem to effect performance much, as far as I could tell
# benchmarking.
#
# This class can be sub-classed to write out different serialized
# reprentations -- subclasses will just override the #serialize
# method. For instance, see JsonWriter.
#
# ## Output
#
# The main functionality this class provides is logic for choosing based on
# settings what file or bytestream to send output to.
#
# You can supply `settings["output_file"]` with a _file path_. LineWriter
# will open up a `File` to write to.
#
# Or you can supply `settings["output_stream"]` with any ruby IO object, such an
# open `File` object or anything else.
#
# If neither are supplied, will write to `$stdout`.
#
# ## Closing the output stream
#
# The LineWriter tries to guess on whether it should call `close` on the output
# stream it's writing to, when the LineWriter instance is closed. For instance,
# if you passed in a `settings["output_file"]` with a path, and the LineWriter
# opened up a `File` object for you, it should close it for you.
#
# But for historical reasons, LineWriter doesn't just use that signal, but tries
# to guess generally on when to call close. If for some reason it gets it wrong,
# just use `settings["close_output_on_close"]` set to `true` or `false`.
# (String `"true"` or `"false"` are also acceptable, for convenience in setting
# options on command line)
class Traject::LineWriter
  attr_reader :settings
  attr_reader :write_mutex, :output_file

  def initialize(argSettings)
    @settings     = argSettings
    @write_mutex  = Mutex.new

    # trigger lazy loading now for thread-safety
    @output_file = open_output_file
  end

  def _write(data)
    output_file.puts(data)
  end


  def serialize(context)
    context.output_hash
  end

  def put(context)
    serialized = serialize(context)
    write_mutex.synchronize do
      _write(serialized)
    end
  end

  def open_output_file
    unless defined? @output_file
      of =
        if settings["output_file"]
          File.open(settings["output_file"], 'w:UTF-8')
        elsif settings["output_stream"]
          settings["output_stream"]
        else
          $stdout
        end
    end
    return of
  end

  def close
    @output_file.close if should_close_stream?
  end

  def should_close_stream?
    if settings["close_output_on_close"].nil?
      (@output_file.nil? || @output_file.tty? || @output_file == $stdout || $output_file == $stderr)
    else
      settings["close_output_on_close"].to_s == "true"
    end
  end


end
