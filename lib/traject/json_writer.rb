require 'json'
require 'traject/line_writer'

# A writer for Traject::Indexer, that just writes out
# all the output as Json. It's newline delimitted json, but
# right now no checks to make sure there is no internal newlines
# as whitespace in the json. TODO, add that.
#
# You can force pretty-printing with setting 'json_writer.pretty_print' of boolean
# true or string 'true'.  Useful mostly for human checking of output.

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