require 'traject/line_writer'

# A writer for Traject::Indexer that outputs each record as a series of
# lines, prefixed by the id, one for each field and it's values.
# Multiple values are separated by pipes

class Traject::DebugWriter < Traject::LineWriter
  def serialize(context)
    idfield = settings["debug_writer.idfield"] || 'id'
    format  = settings['debug_writer.format'] || '%-12s %-25s %s'
    h = context.output_hash
    lines = h.keys.sort.map {|k| format % [h[idfield].first, k, h[k].join(' | ')] }
    lines.push "\n"
    lines.join("\n")
  end    

end