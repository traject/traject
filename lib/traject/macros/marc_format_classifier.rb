module Traject
  module Macros
    # To use the marc_format macro, in your configuration file:
    #
    #     require 'traject/macros/marc_format_classifier'
    #     extend Traject::Macros::MarcFormats
    #
    #     to_field "format", marc_formats
    #
    # See also MarcClassifier which can be used directly for a bit more
    # control.
    module MarcFormats
      # very opionated macro that just adds a grab bag of format/genre/types
      # from our own custom vocabulary, all into one field.
      # You may want to build your own from MarcFormatClassifier functions instead.
      #
      def marc_formats
        lambda do |record, accumulator|
          accumulator.concat Traject::Macros::MarcFormatClassifier.new(record).formats
        end
      end
    end


    # A tool for classifiying MARC records according to format/form/genre/type,
    # just using our own custom vocabulary for those things.
    #
    # used by the `marc_formats` macro, but you can also use it directly
    # for a bit more control.
    class MarcFormatClassifier
      attr_reader :record

      def initialize(marc_record)
        @record = marc_record
      end

      # A very opinionated method that just kind of jams together
      # all the possible format/genre/types into one array of 1 to N elements.
      #
      # If no other values are present, the default value "Other" will be used.
      #
      # See also individual methods which you can use you seperate into
      # different facets or do other custom things.
      def formats(options = {})
        options = {:default => "Other"}.merge(options)

        formats = []

        formats.concat genre

        formats << "Manuscript/Archive" if manuscript_archive?
        formats << "Microform" if microform?
        formats << "Online"    if online?

        # In our own data, if it's an audio recording, it might show up
        # as print, but it's probably not.
        formats << "Print"     if print? && ! (formats.include?("Non-musical Recording") || formats.include?("Musical Recording"))

        # If it's a Dissertation, we decide it's NOT a book
        if thesis?
          formats.delete("Book")
          formats << "Dissertation/Thesis"
        end

        if proceeding?
          formats <<  "Conference"
        end

        if formats.empty?
          formats << options[:default]
        end

        return formats
      end



      # Returns 1 or more values in an array from:
      # Book; Journal/Newspaper; Musical Score; Map/Globe; Non-musical Recording; Musical Recording
      # Image; Software/Data; Video/Film
      #
      # Uses leader byte 6, leader byte 7, and 007 byte 0.
      #
      # Gets actual labels from marc_genre_leader and marc_genre_007 translation maps,
      # so you can customize labels if you want.
      def genre
        marc_genre_leader = Traject::TranslationMap.new("marc_genre_leader")
        marc_genre_007    = Traject::TranslationMap.new("marc_genre_007")

        results = marc_genre_leader[ record.leader.slice(6,2) ] ||
          marc_genre_leader[ record.leader.slice(6)] ||
          record.find_all {|f| f.tag == "007"}.collect {|f| marc_genre_007[f.value.slice(0)]}

        [results].flatten
      end

      # Just checks if it has a 502, if it does it's considered a thesis
      def thesis?
        @thesis_q ||= begin
          ! record.find {|a| a.tag == "502"}.nil?
        end
      end

      # Just checks all $6xx for a $v "Congresses"
      def proceeding?
        @proceeding_q ||= begin
          ! record.find do |field|
            field.tag.slice(0) == '6' &&
                field.subfields.find {|sf| sf.code == "v" && /^\s*(C|c)ongresses\.?\s*$/.match(sf.value) }
          end.nil?
        end
      end

      # Algorithm with help from Chris Case.
      # * If it has any RDA 338, then it's print if it has a value of
      #   volume, sheet, or card.
      # * If it does not have an RDA 338, it's print if and only if it has
      #   no 245$h GMD.
      #
      # * Here at JH, for legacy reasons we also choose to not
      #   call it print if it's already been marked audio, but
      #   we do that in a different method.
      #
      # Note that any record that has neither a 245 nor a 338rda is going
      # to be marked print
      #
      # This algorithm is definitely going to get some things wrong in
      # both directions, with real world data. But seems to be good enough.
      def print?


        rda338 = record.find_all do |field|
          field.tag == "338" && field['2'] == "rdacarrier"
        end

        if rda338.length > 0
          rda338.find do |field|
            field.subfields.find do |sf|
              (sf.code == "a" && %w{volume card sheet}.include?(sf.value)) ||
              (sf.code == "b" && %w{nc no nb}.include?(sf.value))
            end
          end
        else
          normalized_gmd.length == 0 
        end
      end

      # We use marc 007 to determine if this represents an online
      # resource. But sometimes resort to 245$h GMD too.
      def online?
        # field 007, byte 0 c="electronic" byte 1 r="remote" ==> sure Online
        found_007 = record.fields('007').find do |field|
          field.value.slice(0) == "c" && field.value.slice(1) == "r"
        end

        return true if found_007

        # Otherwise, if it has a GMD ["electronic resource"], we count it
        # as online only if NO 007[0] == 'c' exists, cause if it does we already
        # know it's electronic but not remote, otherwise first try would
        # have found it.
        return (normalized_gmd.start_with? "[electronic resource]") && ! record.find {|f| f.tag == '007' && f.value.slice(0) == "c"}
      end

      # if field 007 byte 0 is 'h', that's microform. But many of our microform
      # don't have that. If leader byte 6 is 'h', that's an obsolete way of saying
      # microform. And finally, if GMD is
      def microform?
        normalized_gmd.start_with?("[microform]") ||
        record.leader[6] == "h" ||
        record.find {|f| (f.tag == "007") && (f.value[0] == "h")}
      end

      # Marked as manuscript OR archive.
      def manuscript_archive?
        leader06 = record.leader.slice(6)
        leader08 = record.leader.slice(8)

        # leader 6 t=Manuscript Language Material, d=Manuscript Music,
        # f=Manuscript Cartographic
        #
        # leader 06 = 'b' is obsolete, but if it exists it means archival countrl
        #
        # leader 08 'a'='archival control'
        %w{t d f b}.include?(leader06) || leader08 == "a"
      end

      # downcased version of the gmd, or else empty string
      def normalized_gmd
        @gmd ||= begin
          ((a245 = record['245']) && a245['h'] && a245['h'].downcase) || ""
        end
      end


    end
  end
end
