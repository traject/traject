require 'traject/nokogiri_reader'
require 'traject/macros/nokogiri_macros'
require 'traject/oai_pmh_nokogiri_reader'

module Traject
  class Indexer
    # An indexer sub-class for XML, where the source records in the pipeline are
    # Nokogiri::XML::Document objects. It sets a default reader of NokogiriReader, and
    # includes Traject::Macros::Nokogiri (with `extract_xpath`).
    #
    # See docs on XML use. (TODO)
    class NokogiriIndexer < ::Traject::Indexer
      include Traject::Macros::NokogiriMacros

      def self.default_settings
        @default_settings ||= super.merge("reader_class_name" => "Traject::NokogiriReader")
      end

      # Overridden from base Indexer, try an `id` attribute or element on record.
      def source_record_id_proc
        @source_record_id_proc ||= lambda do |source_xml_record|
          if ( source_xml_record &&
               source_xml_record.kind_of?(Nokogiri::XML::Node) )
            source_xml_record['id'] || (el = source_xml_record.at_xpath('./id') && el.text)
          end
        end
      end
    end
  end
end
