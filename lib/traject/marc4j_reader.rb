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
# Uses the Marc4J MarcPermissiveStreamReader, but sometimes
# in non-permissive mode, according to settings.
#
#
# Settings:
#
# * marc_source.type:     serialization type. default 'binary', also 'xml' or 'json'. (Json is marc-in-json?)
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
    @settings     = Traject::Indexer::Settings.new(default_settings).merge(settings)
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

  def create_marc_reader!
    permissive = settings["marc4j_reader.permissive"].to_s == "true"

    # third arg means 'convert to UTF-8, yes'
    return MarcPermissiveStreamReader.new(input_stream.to_inputstream, permissive, true, settings["marc4j_reader.source_encoding"])
  end

  def each
    while (internal_reader.hasNext)
      marc4j = internal_reader.next
      rubymarc = self.class.convert_marc4j_to_rubymarc(marc4j)
      yield rubymarc
    end
  end

  def self.convert_marc4j_to_rubymarc(marc4j)
    rmarc = MARC::Record.new
    rmarc.leader = marc4j.getLeader.marshal

    marc4j.getControlFields.each do |marc4j_control|
      rmarc.append( MARC::ControlField.new(marc4j_control.getTag(), marc4j_control.getData )  )
    end

    marc4j.getDataFields.each do |marc4j_data|
      rdata = MARC::DataField.new(  marc4j_data.getTag,  marc4j_data.getIndicator1.chr, marc4j_data.getIndicator2.chr )

      marc4j_data.getSubfields.each do |subfield|
        rsubfield = MARC::Subfield.new(subfield.getCode.chr, subfield.getData)
        rdata.append rsubfield
      end

      rmarc.append rdata
    end

    return rmarc
  end

  def default_settings
    {
      "marc_source.type" => "binary",
      "marc4j_reader.permissive" => true,
      "marc4j_reader.source_encoding" => "MARC8"
    }
  end

end