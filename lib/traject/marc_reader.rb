require 'marc'

# A Reader class that can be used with Traject::Indexer.reader, to read
# MARC records.
#
# Includes Enumerable for convenience.
#
# Reads in Marc records using ruby marc. Depends on config variables to
# determine what serialization type to expect, and other parameters controlling
# de-serialization.
#
# NOTE: MarcReader can not handle Marc8 encoding. If you need to read binary
# records in MARC8, use Traject::Marc4JReader instead.
#
# Settings:
#   ["marc_source.type"]  serialization type. default 'binary'
#                 * "binary". Actual marc.
#                 * "xml", MarcXML
#                 * "json". (NOT YET IMPLEMENTED) The "marc-in-json" format, encoded as newline-separated
#                   json. A simplistic newline-separated json, with no comments
#                   allowed, and no unescpaed internal newlines allowed in the json
#                   objects -- we just read line by line, and assume each line is a
#                   marc-in-json. http://dilettantes.code4lib.org/blog/2010/09/a-proposal-to-serialize-marc-in-json/
#   ["marc_reader.xml_parser"] For XML type, which XML parser to tell Marc::Reader
#                              to use. Anything recognized by Marc::Reader :parser
#                              argument. By default, asks Marc::Reader to take
#                              it's best guess as to highest performance available
#                              installed option.
#
#
# Can NOT yet read Marc8, input is always assumed UTF8.
class Traject::MarcReader
  include Enumerable

  attr_reader :settings, :input_stream

  @@best_xml_parser = MARC::XMLReader.best_available

  def initialize(input_stream, settings)
    @settings = Traject::Indexer::Settings.new settings
    @input_stream = input_stream
  end

  # Creates proper kind of ruby MARC reader, depending
  # on settings or guesses.
  def internal_reader
    unless defined? @internal_reader
      @internal_reader =
        case settings["marc_source.type"]
        when "xml"
          parser = settings["marc_reader.xml_parser"] || @@best_xml_parser
          MARC::XMLReader.new(self.input_stream, :parser=> parser)
        else
          MARC::Reader.new(self.input_stream)
        end
    end
    return @internal_reader
  end

  def each(*args, &block)
    self.internal_reader.each(*args, &block)
  end

end