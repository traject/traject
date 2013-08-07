require 'traject'
require 'marc'

# Uses Marc4J to read the marc records, but then translates them to
# ruby-marc before delivering them still, Marc4J is just inside the black
# box.
#
# But one way to get ability to transcode from Marc8. Records it delivers
# are ALWAYS in UTF8, will be transcoded if needed.
#
# Also hope it gives us some performance benefit.
#
# Uses the Marc4J MarcPermissiveStreamReader for binary, but sometimes
# in non-permissive mode, according to settings. Uses the Marc4j MarcXmlReader
# for xml.
#
# NOTE: If you aren't reading in binary records encoded in MARC8, you may
# find the pure-ruby Traject::MarcReader faster; the extra step to read
# Marc4J but translate to ruby MARC::Record adds some overhead.
#
# Settings:
#
# * marc_source.type:     serialization type. default 'binary', also 'xml' (TODO: json/marc-in-json)
#
# * marc4j_reader.permissive:   default true, false to turn off permissive reading. Used as
#                             value to 'permissive' arg of MarcPermissiveStreamReader constructor.
#                             Only used for 'binary'
#
# * marc4j_reader.source_encoding: Only used for 'binary', otherwise always UTF-8.
#         String of the values MarcPermissiveStreamReader accepts:
#         * BESTGUESS  (tries to use MARC leader and believe it, I think)
#         * ISO8859_1
#         * UTF-8
#         * MARC8
#         Default 'BESTGUESS', but marc records in the wild are so wrong here, recommend setting.
#         (will ALWAYS be transcoded to UTF-8 on the way out. We insist.)
#
# * marc4j_reader.jar_dir:   Path to a directory containing Marc4J jar file to use. All .jar's in dir will
#                          be loaded. If unset, uses marc4j.jar bundled with traject.
class Traject::Marc4JReader
  include Enumerable

  attr_reader :settings, :input_stream

  def initialize(input_stream, settings)
    @settings     = Traject::Indexer::Settings.new settings
    @input_stream = input_stream

    ensure_marc4j_loaded!
  end

    # Loads solrj if not already loaded. By loading all jars found
  # in settings["solrj.jar_dir"]
  def ensure_marc4j_loaded!
    unless defined?(MarcPermissiveStreamReader)
      require 'java'

      tries = 0
      begin
        tries += 1
        java_import org.marc4j.MarcPermissiveStreamReader
        java_import org.marc4j.MarcXmlReader
      rescue NameError  => e
        # /Users/jrochkind/code/solrj-gem/lib"

        include_jar_dir = File.expand_path("../../vendor/marc4j/lib", File.dirname(__FILE__))

        jardir = settings["marc4j_reader.jar_dir"] || include_jar_dir
        Dir.glob("#{jardir}/*.jar") do |x|
          require x
        end

        if tries > 1
          raise LoadError.new("Can not find Marc4J java classes")
        else
          retry
        end
      end
    end
  end

  def internal_reader
    @internal_reader ||= create_marc_reader!
  end

  def input_type
    # maybe later add some guessing somehow
    settings["marc_source.type"]
  end

  def create_marc_reader!
    case input_type
    when "binary"
      permissive = settings["marc4j_reader.permissive"].to_s == "true"

      # #to_inputstream turns our ruby IO into a Java InputStream
      # third arg means 'convert to UTF-8, yes'
      MarcPermissiveStreamReader.new(input_stream.to_inputstream, permissive, true, settings["marc4j_reader.source_encoding"])
    when "xml"
      MarcXmlReader.new(input_stream.to_inputstream)
    else
      raise IllegalArgument.new("Unrecgonized marc_source.type: #{input_type}")
    end
  end

  def each
    while (internal_reader.hasNext)
      begin
        marc4j = internal_reader.next
        rubymarc = convert_marc4j_to_rubymarc(marc4j)
      rescue Exception =>e
        msg = "MARC4JReader: Error reading MARC, fatal, re-raising"
        if marc4j
          msg += "\n    001 id: #{marc4j.getControlNumber}"
        end
        msg += "\n    #{Traject::Util.exception_to_log_message(e)}"
        logger.fatal msg
        raise e
      end

      yield rubymarc
    end
  end

  def logger
    @logger ||= (settings[:logger] || Yell.new(STDERR, :level => "gt.fatal")) # null logger)
  end

  def convert_marc4j_to_rubymarc(marc4j)
    rmarc = MARC::Record.new
    rmarc.leader = marc4j.getLeader.marshal

    marc4j.getControlFields.each do |marc4j_control|
      rmarc.append( MARC::ControlField.new(marc4j_control.getTag(), marc4j_control.getData )  )
    end

    marc4j.getDataFields.each do |marc4j_data|
      rdata = MARC::DataField.new(  marc4j_data.getTag,  marc4j_data.getIndicator1.chr, marc4j_data.getIndicator2.chr )

      marc4j_data.getSubfields.each do |subfield|

        # We assume Marc21, skip corrupted data
        # if subfield.getCode is more than 255, subsequent .chr
        # would raise.
        if subfield.getCode > 255
          logger.warn("Marc4JReader: Corrupted MARC data, record id #{marc4j.getControlNumber}, field #{marc4j_data.tag}, corrupt subfield code byte #{subfield.getCode}. Skipping subfield, but continuing with record.")
          next
        end

        rsubfield = MARC::Subfield.new(subfield.getCode.chr, subfield.getData)
        rdata.append rsubfield
      end

      rmarc.append rdata
    end

    return rmarc
  end

end