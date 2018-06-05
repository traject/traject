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

      def translation_map(translation_map_specifier)
        translation_map = Traject::TranslationMap.new(translation_map_specifier)

        lambda do |rec, acc|
          translation_map.translate_array! acc
        end
      end

      def default(default_value)
        lambda do |rec, acc|
          if acc.empty?
            acc << default_value
          end
        end
      end

      def first_only
        lambda do |rec, acc|
          acc.replace Array(acc[0])
        end
      end

      def unique
        lambda do |rec, acc|
          acc.uniq!
        end
      end

      def strip
        lambda do |rec, acc|
          acc.collect! do |v|
            # unicode whitespace class aware
            v.sub(/\A[[:space:]]+/,'').sub(/[[:space:]]+\Z/, '')
          end
        end
      end

      def split(separator)
        lambda do |rec, acc|
          acc.replace( acc.flat_map { |v| v.split(separator) } )
        end
      end

      def append(suffix)
        lambda do |rec, acc|
          acc.collect! { |v| v + suffix }
        end
      end

      def prepend(prefix)
        lambda do |rec, acc|
          acc.collect! { |v| prefix + v }
        end
      end

      def gsub(pattern, replace)
        lambda do |rec, acc|
          acc.collect! { |v| v.gsub(pattern, replace) }
        end
      end

    end
  end
end
