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
    end
  end
end
