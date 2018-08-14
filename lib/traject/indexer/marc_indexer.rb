module Traject
  class Indexer
    # An indexer sub-class that includes "extract_marc" and other macros from
    # Traject::Macros::Marc21, and also adds some marc-specific default settings.
    class MarcIndexer < ::Traject::Indexer
      include Traject::Macros::Marc21

      def self.default_settings
        @default_settings ||= begin
          marc_settings = {
            "reader_class_name"       => "Traject::MarcReader",
            "marc_source.type"        => "binary",
          }
          super.merge(marc_settings)
        end
      end

      # Overridden from base Indexer, to get MARC 001 for log messages.
      def source_record_id_proc
        @source_record_id_proc ||= lambda do |source_marc_record|
          if ( source_marc_record &&
               source_marc_record.kind_of?(MARC::Record) &&
               source_marc_record['001'] )
            source_marc_record['001'].value
          end
        end
      end
    end
  end
end
