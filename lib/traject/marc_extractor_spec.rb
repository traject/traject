# Represents a single specification for extracting data
# from a marc field, like "600abc" or "600|1*|x".
#
# Includes the tag for reference, although this is redundant and not actually used
# in logic, since the tag is also implicit in the overall spec_hash
# with tag => [spec1, spec2]


module Traject
  class MarcExtractor

    # A set of specs
    class SpecSet

      attr_accessor :hash

      def self.new(seedset = {})

        case seedset
          when String, Array
            s      = allocate
            s.hash = Spec.hash_from_string(seedset)
            s
          when Hash
            s    = allocate
            hash = Hash.new
            seedset.each_pair do |k, v|
              hash[k] = Array(v)
            end
            s.hash = hash
            s
          when SpecSet
            seedset
          else
            raise ArgumentError.new, "SpecSet can only be constructed from a string, a hash, or another SpecSet"
        end
      end

      def add(spec)
        @hash[spec.tag] << spec
      end

      def tags
        @hash.keys
      end

      def specs_for_tag(tag)
        @hash[tag] || []
      end

      def specs_matching_field(field, use_alternate_script = false)
        field_tag = field.tag
        if use_alternate_script and (field_tag == ALTERNATE_SCRIPT_TAG)
          field_tag = effective_tag(field)
        end
        specs_for_tag(field_tag).select { |s| s.matches_indicators?(field) }
      end


      def effective_tag(field)
        six = field[SUBFIELD_6]
        if six
          six.encode(six.encoding).byteslice(0, 3)
        else
          ALTERNATE_SCRIPT_TAG
        end
      end

    end

    class Spec
      attr_accessor :tag, :subfields
      attr_reader :indicator1, :indicator2, :byte1, :byte2, :bytes

      # Allow use of a hash to initialize. Should ditch this and use
      # optional keyword args once folks move to 2.x syntax
      def initialize(hash = nil)
        if hash
          hash.each_pair do |key, value|
            self.send("#{key}=", value)
          end
        end
      end

      #  Should subfields extracted by joined, if we have a seperator?
      #  * '630' no subfields specified => join all subfields
      #  * '630abc' multiple subfields specified = join all subfields
      #  * '633a' one subfield => do not join, return one value for each $a in the field
      #  * '633aa' one subfield, doubled => do join after all, will return a single string joining all the values of all the $a's.
      #
      # Last case is handled implicitly at the moment when subfields == ['a', 'a']
      def joinable?
        (self.subfields.nil? || self.subfields.size != 1)
      end

      def indicator1=(ind1)
        ind1 == '*' ? @indicator1 = nil : @indicator1 = ind1.freeze
      end

      def indicator2=(ind2)
        ind2 == '*' ? @indicator2 = nil : @indicator2 = ind2.freeze
      end

      def byte1=(byte1)
        @byte1 = byte1.to_i if byte1
        set_bytes(@byte1, @byte2)
      end

      def byte2=(byte2)
        @byte2 = byte2.to_i if byte2
        set_bytes(@byte1, @byte2)
      end

      def set_bytes(byte1, byte2)
        if byte1 && byte2
          @bytes = ((byte1.to_i)..(byte2.to_i))
        elsif byte1
          @bytes = byte1.to_i
        end
      end

      # Pass in a MARC field, do it's indicators match indicators
      # in this spec? nil indicators in spec mean we don't care, everything
      # matches.
      def matches_indicators?(field)
        return (indicator1.nil? || indicator1 == field.indicator1) &&
            (indicator2.nil? || indicator2 == field.indicator2)
      end

      # Pass in a string subfield code like 'a'; does this
      # spec include it?
      def includes_subfield_code?(code)
        # subfields nil means include them all
        self.subfields.nil? || self.subfields.include?(code)
      end

      # Simple equality definition
      def ==(spec)
        return false unless spec.kind_of?(Spec)

        return (self.tag == spec.tag) &&
            (self.subfields == spec.subfields) &&
            (self.indicator1 == spec.indicator1) &&
            (self.indicator2 == spec.indicator2) &&
            (self.bytes == spec.bytes)
      end


      # Converts from a string marc spec like "008[35]:245abc:700a" to a hash used internally
      # to represent the specification. See comments at head of class for
      # documentation of string specification format.
      #
      #
      # ## Return value
      #
      # The hash returned is keyed by tag, and has as values an array of 0 or
      # or more MarcExtractor::Spec objects representing the specified extraction
      # operations for that tag.
      #
      # It's an array of possibly more than one, because you can specify
      # multiple extractions on the same tag: for instance "245a:245abc"
      #
      # See tests for more examples.

      DATAFIELD_PATTERN    = /\A([a-zA-Z0-9]{3})(\|([a-z0-9\ \*])([a-z0-9\ \*])\|)?([a-z0-9]*)?\Z/
      CONTROLFIELD_PATTERN = /\A([a-zA-Z0-9]{3})(\[(\d+)(-(\d+))?\])\Z/

      def self.hash_from_string(spec_string)
        # hash defaults to []
        hash         = Hash.new

        # Split the string(s) given on colon
        spec_strings = spec_string.is_a?(Array) ? spec_string.map { |s| s.split(/\s*:\s*/) }.flatten : spec_string.split(/\s*:\s*/)

        spec_strings.each do |part|
          if m = DATAFIELD_PATTERN.match(part)

            tag, ind1, ind2, subfields = m[1], m[3], m[4], m[5]

            spec = create_datafield_spec(tag, ind1, ind2, subfields)

            hash[spec.tag] ||= []
            hash[spec.tag] << spec

          elsif m = CONTROLFIELD_PATTERN.match(part)
            tag, byte1, byte2 = m[1], m[3], m[5]

            spec = create_controlfield_spec(tag, byte1, byte2)

            hash[spec.tag] ||= []
            hash[spec.tag] << spec
          else
            raise ArgumentError.new("Unrecognized marc extract specification: #{part}")
          end
        end

        return hash
      end


      # Create a new datafield spec. Most of the logic about how to deal
      # with special characters is built into the Spec class.

      def self.create_datafield_spec(tag, ind1, ind2, subfields)
        spec            = Spec.new(:tag => tag)
        spec.indicator1 = ind1.freeze
        spec.indicator2 = ind2.freeze

        if subfields and !subfields.empty?
          spec.subfields = subfields.split('')
        end

        spec

      end

      # Create a new controlfield spec
      def self.create_controlfield_spec(tag, byte1, byte2)
        spec = Spec.new(:tag => tag.freeze)
        spec.set_bytes(byte1.freeze, byte2.freeze)
        spec
      end


    end
  end

end

