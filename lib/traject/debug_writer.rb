require 'traject/line_writer'

# The Traject::DebugWriter produces a simple, human-readable output format that's
# also amenable to simple computer processing (e.g., with a simple grep).
# It's the output format used when you pass the --debug-mode switch to traject on the command line.
#
# Output format is three columns: id, output field, values (multiple
# values seperated by '|'), and looks something like:
#
#     000001580    edition                   [1st ed.]
#     000001580    format                    Book | Online | Print
#     000001580    geo                       Great Britain
#     000001580    id                        000001580
#     000001580    isbn                      0631126902
#
# ## Settings
#
#  * 'output_file' -- the name of the file to output to (command line -o shortcut).
#  * 'output_stream' -- alternately, the IO stream
#  * 'debug_writer.idfield' -- the solr field from which to pull the record ID (default: 'id')
#  * 'debug_writer.format'  -- How to format the id/solr field/values (default: '%-12s %-25s %s')
#
# By default, with neither output_file nor output_stream provided, writes to stdout, which
# can be useful for debugging diagnosis.
#
# ## Example configuration file
#
#     require 'traject/debug_writer'
#
#     settings do
#       provide "writer_class_name", "Traject::DebugWriter"
#       provide "output_file", "out.txt"
#     end
class Traject::DebugWriter < Traject::LineWriter
  DEFAULT_IDFIELD = 'id'
  DEFAULT_FORMAT  = '%-12s %-25s %s'

  def initialize(*)
    super
    @idfield = settings["debug_writer.idfield"] || DEFAULT_IDFIELD
    @format  = settings['debug_writer.format'] || DEFAULT_FORMAT

    @use_position = (@idfield == 'record_position')

    @already_threw_warning_about_missing_id = false
  end

  def record_number(context)
    return context.position if @use_position
    if context.output_hash.has_key?(@idfield)
      context.output_hash[@idfield].first
    else
      unless @already_threw_warning_about_missing_id
        context.logger.warn "At least one record (#{context.record_inspect}) doesn't define field '#{@idfield}'.
All records are assumed to have a unique id. You can set which field to look in via the setting 'debug_writer.idfield'"
        @already_threw_warning_about_missing_id = true
      end
      "record_num_#{context.position}"
    end
  end

  def serialize(context)
    h       = context.output_hash
    rec_key = record_number(context)
    lines   = h.keys.sort.map { |k| @format % [rec_key, k, (h[k] || []).join(' | ')] }
    lines.push "\n"
    lines.join("\n")
  end

end
