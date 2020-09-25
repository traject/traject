require 'traject/marc_extractor_spec'

module Traject
  # MarcExtractor is a class for extracting lists of strings from a MARC::Record,
  # according to specifications. See Traject::MarcExtractor::Spec for description
  # of string string arguments used to specify extraction. See #initialize for
  # options that can be set controlling extraction.
  #
  # Examples:
  #
  #     array_of_stuff   = MarcExtractor.new("001:245abc:700a").extract(marc_record)
  #     values           = MarcExtractor.new("245a:245abc").extract_marc(marc_record)
  #     seperated_values = MarcExtractor.new("020a:020z").extract(marc_record)
  #     bytes            = MarcExtractor.new("008[35-37]")
  #
  # ## String extraction specifications
  #
  # Extraction directions are supplied in strings, usually as the first
  # parameter to MarcExtractor.new or MarcExtractor.cached. These specifications
  # are also the first parameter to the #marc_extract macro.
  #
  # A String specification is a string (or array of strings) which consists
  # of one or more Data and Control Field Specifications seperated by colons.
  #
  # A Data Field Specification is of the form:
  #
  # * `{tag}{|indicators|}{subfields}`
  # * {tag} is three chars (usually but not neccesarily numeric)
  # * {indicators} are optional two chars enclosed in pipe ('|') characters,
  # * {subfields} are optional list of chars (alphanumeric)
  #
  # indicator spec must be two chars, but one can be * meaning "don't care".
  # space to mean 'blank'
  #
  #     "245|01|abc65:345abc:700|*5|:800"
  #
  # A Control Field Specification is used with tags for control (fixed) fields (ordinarily fields 001-010)
  # and includes a tag and a a byte slice specification.
  #
  #      "008[35-37]:007[5]""
  #      => bytes 35-37 inclusive of any field 008, and byte 5 of any field 007
  #
  # * subfields and indicators can only be provided for marc data/variable fields
  # * byte slice can only be provided for marc control fields (generally tags less than 010)
  #
  # ## Subfield concatenation
  #
  # Normally, for a spec including multiple subfield codes, multiple subfields
  # from the same MARC field will be concatenated into one string separated by spaces:
  #
  #     600 a| Chomsky, Noam x| Philosophy.
  #     600 a| Chomsky, Noam x| Political and social views.
  #     MarcExtractor.new("600ax").extract(record)
  #     # results in two values sent to Solr:
  #     "Chomsky, Noam Philosophy."
  #     "Chomsky, Noam Political and social views."
  #
  # You can turn off this concatenation and leave individual subfields in seperate
  # strings by setting the `separator` option to nil:
  #
  #     MarcExtractor.new("600ax", :separator => nil).extract(record)
  #     # Results in four values being sent to Solr (or 3 if you de-dup):
  #     "Chomksy, Noam"
  #     "Philosophy."
  #     "Chomsky, Noam"
  #     "Political and social views."
  #
  # However, **the default is different for specifications with only a single
  # subfield**, these are by default kept seperated:
  #
  #     020 a| 285197145X a| 9782851971456
  #     MarcExtractor.new("020a:020z").extract(record)
  #     # two seperate strings sent to Solr:
  #     "285197145X"
  #     "9782851971456"
  #
  # For single subfield specifications, you force concatenation by
  # repeating the subfield specification:
  #
  #     MarcExtractor.new("020aa:020zz").extract(record)
  #     # would result in a single string sent to solr for
  #     # the single field, by default space-separated:
  #     "285197145X 9782851971456"
  #
  # ## Note on Performance and MarcExtractor creation and reuse
  #
  # A MarcExtractor is somewhat expensive to create, and has been shown in profiling/
  # benchmarking to be a bottleneck if you end up creating one for each marc record
  # processed.  Instead, a single MarcExtractor should be created, and re-used
  # per MARC record.
  #
  # If you are creating a traject 'macro' method, here's one way to do that,
  # capturing the MarcExtractor under closure:
  #
  #     def some_macro(spec, other_args, whatever)
  #       extractor = MarcExtractor.new( spec )
  #       # ...
  #       return lambda do |record, accumulator, context|
  #          #...
  #          accumulator.concat extractor.extract(record)
  #          #...
  #       end
  #     end
  #
  # In other cases, you may find it convenient to improve performance by
  # using the MarcExtractor#cached method, instead of MarcExtractor#new, to
  # lazily create and then re-use a MarcExtractor object with
  # particular initialization arguments.
  class MarcExtractor
    attr_accessor :options, :spec_set

    ALTERNATE_SCRIPT_TAG = '880'.freeze
    SUBFIELD_6 = '6'.freeze
    EMPTY = [].freeze
    SPACE = ' '.freeze

    # First arg is a specification for extraction of data from a MARC record.
    # Specification can be given in two forms:
    #
    #  * a string specification like "008[35]:020a:245abc", see top of class
    #    for examples. A string specification is most typical argument.
    #  * The output of a previous call to MarcExtractor.parse_string_spec(string_spec),
    #    a 'pre-parsed' specification.
    #
    # Second arg is options:
    #
    # [:separator]  default ' ' (space), what to use to separate
    #               subfield values when joining strings
    #
    # [:alternate_script] default :include, include linked 880s for tags
    #                     that match spec. Also:
    #                     * false => do not include.
    #                     * :only => only include linked 880s, not original
    def initialize(spec, options = {})
      self.options = {
          :separator        => SPACE,
          :alternate_script => :include
      }.merge(options)

      self.spec_set = SpecSet.new(spec)


      # Tags are "interesting" if we have a spec that might cover it
      # By default, interesting tags are those represented by keys in spec_hash.
      # Add them unless we only care about alternate scripts.
      unless options[:alternate_script] == :only
        self.spec_set.tags.each { |tag| show_interest_in_tag(tag) }
      end

      # If we *are* interested in alternate scripts, add the 880
      if options[:alternate_script] != false
        @fetch_alternate_script = true
        show_interest_in_tag(ALTERNATE_SCRIPT_TAG)
      else
        @fetch_alternate_script = false
      end

      @interesting_tags_list = @interesting_tags_hash.keys

      self.freeze
    end


    # Declare that we're interested in a tag
    def show_interest_in_tag(tag)
      @interesting_tags_hash      ||= {}
      @interesting_tags_hash[tag.freeze] = true
    end

    # Check to see if a tag is interesting (meaning it may be covered by a spec
    # and the passed-in options about alternate scripts)
    def interesting_tag?(tag)
      return @interesting_tags_hash.include?(tag)
    end

    # All the "interesting" tags
    def interesting_tags
      @interesting_tags_list
    end


    # Takes the same arguments as MarcExtractor.new, but will re-use an existing
    # cached MarcExtractor already created with given initialization arguments,
    # if available.
    #
    # This can be used to increase performance of indexing routines, as
    # MarcExtractor creation has been shown via profiling/benchmarking
    # to be expensive.
    #
    # Cache is thread-local, so should be thread-safe.
    #
    # You should _not_ modify the state of any MarcExtractor retrieved
    # via cached, as the MarcExtractor will be re-used and shared (possibly
    # between threads even!). We try to use ruby #freeze to keep you from doing so,
    # although if you try hard enough you can surely find a way to do something
    # you shouldn't.
    #
    #     extractor = MarcExtractor.cached("245abc:700a", :separator => nil)
    def self.cached(*args)
      cache = (Thread.current[:marc_extractor_cached] ||= Hash.new)
      return (cache[args] ||= Traject::MarcExtractor.new(*args).freeze)
    end


    # Returns array of strings from a MARC::Record, extracted values. May be empty array.
    def extract(marc_record)
      results = []

      self.each_matching_line(marc_record) do |field, spec|
        if control_field?(field)
          results << (spec.bytes ? field.value.byteslice(spec.bytes) : field.value)
        else
          results.concat collect_subfields(field, spec)
        end
      end

      return results
    end

    # Yields a block for every line in source record that matches
    # spec. First arg to block is MARC::DataField or ControlField, second
    # is the MarcExtractor::Spec that it matched on. May take account
    # of options such as :alternate_script
    #
    # Third (optional) arg to block is self, the MarcExtractor object, useful for custom
    # implementations.
    def each_matching_line(marc_record)
      marc_record.fields(interesting_tags).each do |field|

        specs_covering_field(field).each do |spec|
            yield(field, spec, self)
        end

      end
    end

    # line each_matching_line, takes a block to process each matching line,
    # but collects results of block into an array -- flattens any subarrays for you!
    #
    # Useful for re-use of this class for custom processing
    #
    # yields the MARC Field, the MarcExtractor::Spec object, the MarcExtractor object.
    def collect_matching_lines(marc_record)
      results = []
      self.each_matching_line(marc_record) do |field, spec, extractor|
        results.concat [yield(field, spec, extractor)].flatten
      end
      return results
    end


    # Pass in a marc data field and a Spec object with extraction
    # instructions, returns an ARRAY of one or more strings, subfields extracted
    # and processed per spec. Takes account of options such
    # as :separator
    #
    # Always returns array, sometimes empty array.
    def collect_subfields(field, spec)
      subfields = field.subfields.collect do |subfield|
        subfield.value if spec.includes_subfield_code?(subfield.code)
      end.compact

      return subfields if subfields.empty? # empty array, just return it.

      if options[:separator] && spec.joinable?
        subfields = [subfields.join(options[:separator])]
      end

      return subfields
    end


    # Find Spec objects, if any, covering extraction from this field.
    # Returns an array of 0 or more MarcExtractor::Spec objects
    #
    # Returns an empty array in case of no matching extraction specs.
    def specs_covering_field(field)
      return [] unless interesting_tag?(field.tag)
      self.spec_set.specs_matching_field(field, @fetch_alternate_script)
    end


    def control_field?(field)
      # should the MARC gem have a more efficient way to do this,
      # define #control_field? on both ControlField and DataField?
      return field.kind_of? MARC::ControlField
    end

    def freeze
      self.options.freeze
      self.spec_set.freeze
      super
    end


  end
end
