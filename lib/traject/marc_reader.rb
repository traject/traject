require 'marc'
require 'traject/ndj_reader'

# `Traject::MarcReader` uses pure ruby marc gem to parse MARC records. It
# can read MARC ISO 2709 ('binary'), MARC-XML, and Marc-in-json (newline-delimited-json).
#
# Marc4JReader is an alternative to this class, powered by Marc4J. You may be interested
# in comparing for performance, under your particular use case. To use it, you'll need
# the gem traject-marc4j_reader.
#
# By default assumes binary MARC encoding, please set marc_source.type setting
# for XML or json. If binary, please set marc_source.encoding with char encoding.
#
# ## Settings

# * "marc_source.type":  serialization type. default 'binary'
#       * "binary". standard ISO 2709 "binary" MARC format,
#           will use ruby-marc MARC::Reader (Note, if you are using
#          type 'binary', you probably want to also set 'marc_source.encoding')
#       * "xml", MarcXML, will use ruby-marc MARC::XMLReader
#       * "json" The "marc-in-json" format, encoded as newline-separated
#         json. (synonym 'ndj'). A simplistic newline-separated json, with no comments
#         allowed, and no unescpaed internal newlines allowed in the json
#         objects -- we just read line by line, and assume each line is a
#         marc-in-json. http://dilettantes.code4lib.org/blog/2010/09/a-proposal-to-serialize-marc-in-json/
#         will use Traject::NDJReader which uses MARC::Record.new_from_hash.
# * "marc_source.encoding": Only used for marc_source.type 'binary', character encoding
#         of the source marc records. Can be any
#         encoding recognized by ruby, OR 'MARC-8'.  For 'MARC-8', content will
#         be transcoded (by ruby-marc) to UTF-8 in internal MARC::Record Strings.
#         Default nil, meaning let MARC::Reader use it's default, which will
#         be your system's Encoding.default_external, which will probably be UTF-8.
#         (but may be something unexpected/undesired on Windows, where you may want to set this explicitly.)
#         Right now Traject::MarcReader is hard-coded to transcode to UTF-8 as
#         an internal encoding.
# * "marc_reader.xml_parser": For XML type, which XML parser to tell Marc::Reader
#         to use. Anything recognized by [Marc::Reader :parser
#         argument](http://rdoc.info/github/ruby-marc/ruby-marc/MARC/XMLReader).
#         By default, asks Marc::Reader to take
#         it's best guess as to highest performance available
#         installed option. Probably best to leave as default.
#
# ## Example
#
# In a configuration file:
#
#     require 'traject/marc_reader'
#
#     settings do
#       provide "reader_class_name", "Traject::MarcReader"
#       provide "marc_source.type", "xml"
#     end
#
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
        when 'json'
          Traject::NDJReader.new(self.input_stream, settings)
        else
          args = { :invalid => :replace }
          args[:external_encoding] = settings["marc_source.encoding"]
          MARC::Reader.new(self.input_stream, args)
        end
    end
    return @internal_reader
  end

  def each(*args, &block)
    self.internal_reader.each(*args, &block)
  end

end
