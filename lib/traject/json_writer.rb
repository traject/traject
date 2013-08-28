require 'json'
require 'thread'

# A writer for Traject::Indexer, that just writes out
# all the output as Json. It's newline delimitted json, but
# right now no checks to make sure there is no internal newlines
# as whitespace in the json. TODO, add that.
#
# Should be thread-safe (ie, multiple worker threads can be calling #put
# concurrently), by wrapping write to actual output file in a mutex synchronize.
# This does not seem to effect performance much, as far as I could tell
# benchmarking.
#
# You can force pretty-printing with setting 'json_writer.pretty_print' of boolean
# true or string 'true'.  Useful mostly for human checking of output.
#
# Output will be sent to settings["output_file"] string path, or else
# settings["output_stream"] (ruby IO object), or else stdout.
class Traject::JsonWriter
  attr_reader :settings
  attr_reader :write_mutex

  def initialize(argSettings)
    @settings     = argSettings
    @write_mutex  = Mutex.new

    # trigger lazy loading now for thread-safety
    output_file
  end

  def put(context)
    hash = context.output_hash

    serialized =
      if settings["json_writer.pretty_print"]
        JSON.pretty_generate(hash)
      else
        JSON.generate(hash)
      end
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