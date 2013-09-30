require 'traject/line_writer'

# A writer for Traject::Indexer that outputs each record as a series of
# lines, prefixed by the id, one for each field and it's values.
# Multiple values are separated by pipes
#
# Applicable settings:
#
#  * 'output_file' -- the name of the file to output to
#  * 'output_stream' -- alternately, the IO stream
#  * 'debug_writer.idfield' -- the solr field from which to pull the record ID (default: 'id')
#  * 'debug_writer.format'  -- How to format the id/solr field/values (default: '%-12s %-25s %s')
class Traject::DebugWriter < Traject::LineWriter
  DEFAULT_FORMAT = '%-12s %-25s %s'
  DEFAULT_IDFIELD = 'id'
  
  def serialize(context)
    idfield = settings["debug_writer.idfield"] || DEFAULT_IDFIELD
    format  = settings['debug_writer.format']  || DEFAULT_FORMAT
    h = context.output_hash
    lines = h.keys.sort.map {|k| format % [h[idfield].first, k, h[k].join(' | ')] }
    lines.push "\n"
    lines.join("\n")
  end    

end