require 'json'
require 'traject/line_writer'

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
class Traject::JsonWriter < Traject::LineWriter

  def serialize(context)
    hash = context.output_hash
    if settings["json_writer.pretty_print"]
      JSON.pretty_generate(hash)
    else
      JSON.generate(hash)
    end
  end    

end