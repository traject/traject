require 'json'

# A writer for Traject::Indexer, that just writes out
# all the output as Json. It's newline delimitted json, but
# right now no checks to make sure there is no internal newlines
# as whitespace in the json. TODO, add that. 
#
# Not currently thread-safe (have to make sure whole object and newline
# get written without context switch. Can be made so.)
#
# You can force pretty-printing with setting 'json_writer.pretty_print' of boolean
# true or string 'true'.  Useful mostly for human checking of output. 
#
# Output will be sent to settings["output_file"] string path, or else
# settings["output_stream"] (ruby IO object), or else stdout. 
class Traject::JsonWriter
  attr_reader :settings

  def initialize(argSettings)
    @settings = argSettings
  end

  def put(hash)
    serialized = 
      if settings["json_writer.pretty_print"]
        JSON.pretty_generate(hash)
      else
        JSON.generate(hash)
      end
    output_file.puts(serialized)
  end

  def output_file
    unless defined? @output_file
      @output_file = 
        if settings["output_file"]
          File.open(settings["output_file"])
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