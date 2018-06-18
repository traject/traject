module Traject
  class NokogiriReader
    include Enumerable

    attr_reader :settings, :input_stream

    def initialize(input_stream, settings)
      @settings = Traject::Indexer::Settings.new settings
      @input_stream = input_stream
      validate_each_record_xpath
    end

    def each_record_xpath
      @each_record_xpath = settings["nokogiri_reader.each_record_xpath"]
    end

    protected def validate_each_record_xpath
      components = each_record_xpath.split('/')
      components.each do |component|
        namespace, element = component.split(':')
        unless element
          # there was no namespace
          namespace, element = nil, namespace
        end

        if namespace
          namespace = default_namespaces[namespace]
          if namespace.nil?
            raise ArgumentError, "To use a namespace in each_record_xpath, it has to be registered with nokogiri_reader.default_namespaces"
          end
        end
      end

      each_record_xpath
    end

    # Spec object that can test for match to our tiny xpath subset.
    #  *  `//path/to/record`, or just `//record`
    #  *  or rooted at root, `./path/to`, `path/to`, `./path/to` (all equivalent)
    #
    # gotten from setting "xml.each_record_xpath"
    def path_matcher
      path_spec =

      @path_matcher ||= PathMatcher.new(each_record_xpath, namespaces: default_namespaces)
    end

    def default_namespaces
      @default_namespaces ||= (settings["nokogiri_reader.default_namespaces"] || {}).tap { |ns|
        unless ns.kind_of?(Hash)
          raise ArgumentError, "nokogiri_reader.default_namespaces must be a hash, not: #{ns.inspect}"
        end
      }
    end

    def each
      reader = Nokogiri::XML::Reader(input_stream)
      # We're guessing using a string will be more efficient than an array
      path_stack = ""

      reader.each do |reader_node|
        if reader_node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
          path_matcher.push(reader_node)

          if path_matcher.match?
            # yeah, sadly we got to have nokogiri parse it again
            yield Nokogiri::XML.parse(reader_node.outer_xml)
          end
        end

        if reader_node.node_type == Nokogiri::XML::Reader::TYPE_END_ELEMENT
          path_matcher.pop
        end
      end
    end

    private

    # initialized with the specification (a very small subset of xpath) for
    # what records to yield-on-each.  Tests to see if a Nokogiri::XML::Reader
    # node matches spec.
    #
    #    '//record'
    # or anchored to root:
    #   '/body/head/meta' same thing as './body/head/meta' or 'head/meta'
    #
    # Elements can (and must, to match) have XML namespaces, if and only if
    # they are registered with settings nokogiri_reader.default_namespaces
    class PathMatcher
      attr_reader :path_spec, :namespaces, :inverted_namespaces, :current_path
      def initialize(str_spec, namespaces: {})
        @inverted_namespaces  = namespaces.invert
        @current_path         = ""
        @floating             = false

        if str_spec.start_with?('//')
          str_spec = str_spec.slice(2..-1)
          @floating = true
        else
          str_spec = str_spec.slice(1..-1) if str_spec.start_with?(".")
          str_spec = "/" + str_spec unless str_spec.start_with?("/")
        end

        @path_spec = str_spec # a string again for ultra fast matching, we think.
      end

      # adds a component to slash-separated current_path, with namespace prefix.
      def push(reader_node)
        namespace_prefix = reader_node.namespace_uri && inverted_namespaces[reader_node.namespace_uri]
        node_str = if namespace_prefix
          namespace_prefix + ":" + reader_node.name
        else
          reader_node.name
        end

        current_path << ("/" + node_str)
      end

      # removes the last slash-separated component from current_path
      def pop
        current_path.slice!( current_path.rindex('/')..-1 )
      end

      def floating?
        !!@floating
      end

      def match?
        if floating?
          current_path.end_with?(path_spec)
        else
          current_path == path_spec
        end
      end
    end
  end
end
