module Traject
  module Macros
    module NokogiriMacros

      def default_namespaces
        @default_namespaces ||= (settings["nokogiri.namespaces"] || {}).tap { |ns|
          unless ns.kind_of?(Hash)
            raise ArgumentError, "nokogiri.namespaces must be a hash, not: #{ns.inspect}"
          end
        }
      end

      def extract_xpath(xpath, ns: {}, to_text: true)
        if ns && ns.length > 0
          namespaces = default_namespaces.merge(ns)
        else
          namespaces = default_namespaces
        end

        lambda do |record, accumulator|
          result = record.xpath(xpath, namespaces)

          if to_text
            # take all matches, for each match take all
            # text content, join it together separated with spaces
            # Make sure to avoid text content that was all blank, which is "between the children"
            # whitespace.
            result = result.collect do |n|
              if n.kind_of?(Nokogiri::XML::Attr)
                # attribute value
                n.value
              else
                # text from node
                n.xpath('.//text()').collect(&:text).tap do |arr|
                  arr.reject! { |s| s =~ (/\A\s+\z/) }
                end.join(" ")
              end
            end
          else
            # just put all matches in accumulator as Nokogiri::XML::Node's
            result = result.to_a
          end

          accumulator.concat result
        end
      end
    end
  end
end
