module Traject
  module Macros
    # Macros intended to be mixed into an Indexer and used in config
    # as second or further args to #to_field, to transform existing accumulator values.
    #
    # They have the same form as any proc/block passed to #to_field, but
    # operate on an existing accumulator, intended to be used as non-first-step
    # transformations.
    #
    # Some of these are extracted from extract_marc options, so they can be
    # used with any first-step extract methods.  Some informed by current users.
    module Transformation

      # Maps all values on accumulator through a  Traject::TranslationMap.
      #
      # A Traject::TranslationMap is hash-like mapping from input to output, usually
      # defined in a yaml or dot-properties file, which can be looked up in load path
      # with a file name as arg. See [Traject::TranslationMap](../translation_map.rb)
      # header coments for details.
      #
      # Using this macro, you can pass in one TranslationMap initializer arg, but you can
      # also pass in multiple, and they will be merged into each other (last one last), so
      # you can use this to apply over-rides: Either from another on-disk map, or even from
      # an inline hash (since a Hash is a valid TranslationMap initialization arg too).
      #
      # @example
      #     to_field("something"), to_field "cataloging_agency", extract_marc("040a"), translation_map("marc_040a")
      #
      # @example with override
      #     to_field("something"), to_field "cataloging_agency", extract_marc("040a"), translation_map("marc_040a", "local_marc_040a")
      #
      # @example with multiple overrides, including local hash
      #     to_field("something"), to_field "cataloging_agency", extract_marc("040a"), translation_map("marc_040a", "local_marc_040a", {"DLC" => "U.S. LoC"})
      def translation_map(*translation_map_specifier)
        translation_map = translation_map_specifier.
          collect { |spec| Traject::TranslationMap.new(spec) }.
          reduce(:merge)

        lambda do |rec, acc|
          translation_map.translate_array! acc
        end
      end

      # Pass in a proc/lambda arg or a block (or both), that will be called on each
      # value already in the accumulator, to transform it. (Ie, with `#map!`/`#collect!` on your proc(s)).
      #
      # Due to how ruby syntax precedence works, the block form is probably not too useful
      # in traject config files, except with the `&:` trick.
      #
      # The "stabby lambda" may be convenient for passing an explicit proc argument.
      #
      # You can pass both an explicit proc arg and a block, in which case the proc arg
      # will be applied first.
      #
      # @example
      #    to_field("something"), extract_marc("something"), transform(&:upcase)
      #
      # @example
      #    to_field("something"), extract_marc("something"), transform(->(val) { val.tr('^a-z', "\uFFFD") })
      def transform(a_proc=nil, &block)
        unless a_proc || block
          raise ArgumentError, "Needs a transform proc arg or block arg"
        end

        transformer_callable = if a_proc && block
          # need to make a combo wrapper.
          ->(val) { block.call(a_proc.call(val)) }
        elsif a_proc
          a_proc
        else
          block
        end

        lambda do |rec, acc|
          acc.collect! do |value|
            transformer_callable.call(value)
          end
        end
      end

      # Adds a literal to accumulator if accumulator was empty
      #
      # @example
      #      to_field "title", extract_marc("245abc"), default("Unknown Title")
      def default(default_value)
        lambda do |rec, acc|
          if acc.empty?
            acc << default_value
          end
        end
      end

      # Removes all but the first value from accumulator, if more values were present.
      #
      # @example
      #     to_field "main_author", extract_marc("100"), first_only
      def first_only
        lambda do |rec, acc|
          # kind of esoteric, but slice used this way does mutating first, yep
          acc.slice!(1, acc.length)
        end
      end


      # calls ruby `uniq!` on accumulator, removes any duplicate values
      #
      # @example
      #     to_field "something", extract_marc("245:240"), unique
      def unique
        lambda do |rec, acc|
          acc.uniq!
        end
      end


      # For each value in accumulator, remove all leading or trailing whitespace
      # (unique aware). Like ruby #strip, but whitespace-aware
      #
      # @example
      #     to_field "title", extract_marc("245"), strip
      def strip
        lambda do |rec, acc|
          acc.collect! do |v|
            # unicode whitespace class aware
            v.sub(/\A[[:space:]]+/,'').sub(/[[:space:]]+\Z/, '')
          end
        end
      end

      # Run ruby `split` on each value in the accumulator, with separator
      # given, flatten all results into single array as accumulator.
      # Will generally result in more individual values in accumulator as output than were
      # there in input, as input values are split up into multiple values.
      def split(separator)
        lambda do |rec, acc|
          acc.replace( acc.flat_map { |v| v.split(separator) } )
        end
      end

      # Append argument to end of each value in accumulator.
      def append(suffix)
        lambda do |rec, acc|
          acc.collect! { |v| v + suffix }
        end
      end

      # prepend argument to beginning of each value in accumulator.
      def prepend(prefix)
        lambda do |rec, acc|
          acc.collect! { |v| prefix + v }
        end
      end

      # Run ruby `gsub` on each value in accumulator, with pattern and replace value given.
      def gsub(pattern, replace)
        lambda do |rec, acc|
          acc.collect! { |v| v.gsub(pattern, replace) }
        end
      end

      # Run ruby `delete_if` on the accumulator for values that include or are equal to arg.
      # It will also accept an array, set, regex pattern, proc or lambda as an arugment.
      #
      # @example
      #   to_field "creator_facet", extract_marc("100abcdq"), delete_if(/foo/)
      def delete_if(arg)
        p = if arg.respond_to? :include?
              proc { |v| arg.include?(v) }
            else
              proc { |v| arg === v }
            end

        ->(_, acc) { acc.delete_if(&p) }
      end

      # Run ruby `select!` on the accumulator for values that include or are equal to arg.
      # It accepts an array, set, regex pattern, proc or lambda as an arugument.
      #
      # @example
      #   to_field "creator_facet", extract_marc("100abcdq"), select(->(v) { v != "foo" })
      def select(arg)
        p = if arg.respond_to? :include?
              proc { |v| arg.include?(v) }
            else
              proc { |v| arg === v }
            end

        ->(_, acc) { acc.select!(&p) }
      end
    end
  end
end
