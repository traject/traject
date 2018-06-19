module Traject
  class Indexer
    # An indexer sub-class that includes "extract_marc" and other macros from
    # Traject::Macros::Marc21, and also adds some marc-specific default settings.
    class MarcIndexer < ::Traject::Indexer
      include Traject::Macros::Marc21

      def self.default_settings
        @default_settings ||= begin
          is_jruby = defined?(JRUBY_VERSION)

          marc_settings = {
            "reader_class_name"       => is_jruby ? "Traject::Marc4JReader" : "Traject::MarcReader",
            "marc_source.type"        => "binary",
          }
          if is_jruby
            marc_settings["marc4j_reader.permissive"] = true
          end
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
