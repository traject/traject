require 'json'
require 'traject/line_writer'

# The JsonWriter outputs one JSON hash per record, separated by newlines.
#
# It's newline delimitted json, which should be suitable for being
# read by simple NDJ readers. (TODO: We have no checks right now to
# make sure the standard json serializers we're using don't put any
# internal newlines as whitespace in the json. Which would break NDJ
# reading. Should we?)
#
# Should be thread-safe (ie, multiple worker threads can be calling #put
# concurrently), because output to file is wrapped in a mutex synchronize.
# This does not seem to effect performance much, as far as I could tell
# benchmarking.
#
# ## Settings
#
# * output_file A filename to send output; default will use stdout.
#
# * json_writer.pretty_print: [default: false]: Pretty-print (e.g., include newlines, indentation, etc.)
# each JSON record instead of just mashing it all together on one line. The default, no pretty-printing option
# produces one record per line, easy to process with another program.
#
# ## Example output
#
# Without pretty printing, you end up with something like this (just two records shown):
#
#     {"id":["000001118"],"oclc":["ocm00085737"],"sdrnum":["sdr-nrlf.b170195454"],"isbn":["0137319924"],"lccn":["73120791"],"mainauthor":["Behavioral and Social Sciences Survey Committee. Psychiatry Panel."],"author":["Behavioral and Social Sciences Survey Committee. Psychiatry Panel.","Hamburg, David A., 1925-"],"author2":["Behavioral and Social Sciences Survey Committee. Psychiatry Panel.","Hamburg, David A., 1925-"],"authorSort":["Behavioral and Social Sciences Survey Committee. Psychiatry Panel."],"author_top":["Behavioral and Social Sciences Survey Committee. Psychiatry Panel.","Edited by David A. Hamburg.","Hamburg, David A., 1925- ed."],"title":["Psychiatry as a behavioral science."],"title_a":["Psychiatry as a behavioral science."],"title_ab":["Psychiatry as a behavioral science."],"title_c":["Edited by David A. Hamburg."],"titleSort":["Psychiatry as a behavioral science"],"title_top":["Psychiatry as a behavioral science."],"title_rest":["A Spectrum book"],"series2":["A Spectrum book"],"callnumber":["RC327 .B41"],"broad_subject":["Medicine"],"pubdate":[1970],"format":["Book","Online","Print"],"publisher":["Prentice-Hall"],"language":["English"],"language008":["eng"],"editor":["David A. Hamburg."]}
#     {"id":["000000794"],"oclc":["ocm00067181"],"lccn":["78011026"],"mainauthor":["Clark, Albert Curtis, 1859-1937."],"author":["Clark, Albert Curtis, 1859-1937."],"authorSort":["Clark, Albert Curtis, 1859-1937."],"author_top":["Clark, Albert Curtis, 1859-1937."],"title":["The descent of manuscripts.","descent of manuscripts."],"title_a":["The descent of manuscripts.","descent of manuscripts."],"title_ab":["The descent of manuscripts.","descent of manuscripts."],"titleSort":["descent of manuscripts"],"title_top":["The descent of manuscripts."],"callnumber":["PA47 .C45 1970"],"broad_subject":["Language & Literature"],"pubdate":[1918],"format":["Book","Online","Print"],"publisher":["Clarendon Press"],"language":["English"],"language008":["eng"]}
#
# ## Example configuration file
#
#     require 'traject/json_writer'
#
#     settings do
#       provide "writer_class_name", "Traject::JsonWriter"
#       provide "output_file", "out.json"
#     end
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
