module Traject
  # Take a hash that's the output of #parse_string_spec, return
  # an array of strings extracted from a marc record accordingly
  #
  #  extractor = MarcExtractor.106new(record, spec_hash_options)
  #  array_of_values = extractor.extract
  #
  class MarcExtractor
    attr_accessor :options, :marc_record, :spec_hash
    # Take a hash that's the output of #parse_string_spec, return
    # an array of strings extracted from a marc record accordingly
    #
    # options:
    #
    # [:seperator]  default ' ' (space), what to use to seperate
    #               subfield values when joining strings
    #
    # [:alternate_script] default :include, include linked 880s for tags
    #                     that match spec. Also:
    #                     * false => do not include. 
    #                     * :only => only include linked 880s, not original
    def initialize(marc_record, spec_hash, options = {})
      self.options = {
        :seperator => ' ',
        :alternate_script => :include
      }.merge(options)

      self.marc_record = marc_record
      self.spec_hash = spec_hash
    end

    # Returns array of strings, extracted values
    def extract
      results = []

      self.each_matching_line do |field, spec|
        if control_field?(field)
          results << (spec[:bytes] ? field.value.byteslice(spec[:bytes]) : field.value)
        else
          results.concat collect_subfields(field, spec)
        end
      end

      return results
    end

    # Yields a block for every line in source record that matches
    # spec. First arg to block is MARC::Field (control or data), second
    # is the hash specification that it matched on. May take account
    # of options such as :alternate_script
    def each_matching_line
      self.marc_record.each do |field|
        if (spec = spec_covering_field(field)) && matches_indicators(field, spec)
          yield(field, spec)
        end
      end
    end

    # Pass in a marc data field and a hash spec, returns
    # an ARRAY of one or more strings, subfields extracted
    # and processed per spec. Takes account of options such
    # as :seperator
    def collect_subfields(field, spec)
      subfields = field.subfields.collect do |subfield|
        subfield.value if spec[:subfields].nil? || spec[:subfields].include?(subfield.code)
      end.compact

      return options[:seperator] ? [ subfields.join( options[:seperator]) ] : subfields
    end

    # Is there a spec covering extraction from this field?
    # May return true on 880's matching other tags depending
    # on value of :alternate_script
    # if :alternate_script is :only, will return original spec when field is an 880.
    # otherwise will always return nil for 880s, you have to handle :alternate_script :include
    # elsewhere, to add in the 880 in the right order
    def spec_covering_field(field)
      #require 'pry'
      #binding.pry if field.tag == "880"

      if field.tag == "880" && options[:alternate_script] != false
        # pull out the spec for corresponding original marc tag this 880 corresponds to
        # Due to bug in jruby https://github.com/jruby/jruby/issues/886 , we need
        # to do this weird encode gymnastics
        orig_field = field["6"].encode("ascii").byteslice(0,3)
        field["6"] && self.spec_hash[  orig_field  ]
      elsif options[:alternate_script] != :only
        self.spec_hash[field.tag]
      end
    end

    def control_field?(field)
      # should the MARC gem have a more efficient way to do this,
      # define #control_field? on both ControlField and DataField?
      return field.kind_of? MARC::ControlField
    end

    # a marc field, and an individual spec hash, {:subfields => array, :indicators => array}
    def matches_indicators(field, spec)
      return true if spec[:indicators].nil?

      return (spec[:indicators][0].nil? || spec[:indicators][0] == field.indicator1) &&
        (spec[:indicators][1].nil? || spec[:indicators][1] == field.indicator2)
    end
  end
end
