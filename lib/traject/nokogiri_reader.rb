module Traject
  class NokogiriReader
    include Enumerable

    attr_reader :settings, :input_stream

    def initialize(input_stream, settings)
      @settings = Traject::Indexer::Settings.new settings
      @input_stream = input_stream
      default_namespaces # trigger validation
      validate_each_record_xpath
    end

    def each_record_xpath
      @each_record_xpath = settings["nokogiri_reader.each_record_xpath"]
    end

    protected def validate_each_record_xpath
      return unless each_record_xpath

      components = each_record_xpath.split('/')
      components.each do |component|
        prefix, element = component.split(':')
        unless element
          # there was no namespace
          prefix, element = nil, prefix
        end

        # We don't support brackets or any xpath beyond the MOST simple.
        # Catch a few we can catch.
        if element =~ /::/ || element =~ /[\[\]]/
          raise ArgumentError, "each_record_xpath: Only very simple xpaths supported. '//some/path' or '/some/path'. Not: #{each_record_xpath.inspect}"
        end

        if prefix
          ns_uri = default_namespaces[prefix]
          if ns_uri.nil?
            raise ArgumentError, "each_record_xpath: Can't find namespace prefix '#{prefix}' in '#{each_record_xpath}'. To use a namespace in each_record_xpath, it has to be registered with nokogiri_reader.default_namespaces: #{default_namespaces.inspect}"
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
    def path_tracker
      @path_tracker ||= PathTracker.new(each_record_xpath, namespaces: default_namespaces)
    end

    def default_namespaces
      @default_namespaces ||= (settings["nokogiri_reader.default_namespaces"] || {}).tap { |ns|
        unless ns.kind_of?(Hash)
          raise ArgumentError, "nokogiri_reader.default_namespaces must be a hash, not: #{ns.inspect}"
        end
      }
    end

    def each
      unless each_record_xpath
        # forget streaming, just read it and return it once, done.
        yield Nokogiri::XML.parse(input_stream)
        return
      end

      reader = Nokogiri::XML::Reader(input_stream)

      reader.each do |reader_node|
        if reader_node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
          path_tracker.push(reader_node)

          if path_tracker.match?
            # yeah, sadly we got to have nokogiri parse it again
            doc = Nokogiri::XML.parse(reader_node.outer_xml)
            yield path_tracker.fix_namespaces(doc)
          end
        end

        if reader_node.node_type == Nokogiri::XML::Reader::TYPE_END_ELEMENT
          path_tracker.pop
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
    #
    # sadly JRuby Nokogiri has an incompatibility with true nokogiri, and
    # doesn't preserve our namespaces on outer_xml,
    # so in JRuby we have to track them ourselves, and then also do yet ANOTHER
    # parse in nokogiri. This may make this in Java even LESS performant, I'm afraid.
    class PathTracker
      attr_reader :path_spec, :inverted_namespaces, :current_path, :namespaces_stack
      def initialize(str_spec, namespaces: {})
        @inverted_namespaces  = namespaces.invert
        # We're guessing using a string will be more efficient than an array
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

        @namespaces_stack = []
      end

      def is_jruby?
        unless defined?(@is_jruby)
          @is_jruby = defined?(JRUBY_VERSION)
        end
        @is_jruby
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

        if is_jruby?
          namespaces_stack << reader_node.namespaces
        end
      end

      # removes the last slash-separated component from current_path
      def pop
        current_path.slice!( current_path.rindex('/')..-1 )

        if is_jruby?
          namespaces_stack.pop
        end
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

      def fix_namespaces(doc)
        if is_jruby?
          # Only needed in jruby, nokogiri's jruby implementation isn't weird
          # around namespaces in exactly the same way as MRI. We need to keep
          # track of the namespaces in outer contexts ourselves, and then see
          # if they are needed ourselves. :(
          namespaces = namespaces_stack.compact.reduce({}, :merge)
          namespaces.each_pair do |attrib, uri|
            if attrib == "xmlns"
              ns_prefix = nil
            else
              ns_prefix = attrib.sub(/\Axmlns:/, '')
            end

            # gotta make sure it's actually used in the doc to not add it
            # unecessarily. GAH.
            if ns_prefix != nil &&
                  doc.xpath("//*[starts-with(name(), '#{ns_prefix}:')][1]").empty? &&
                  doc.xpath("//@*[starts-with(name(), '#{ns_prefix}:')][1]").empty?
              next
            end
            if ns_prefix == nil
              doc.root.default_namespace = uri
              # OMG nokogiri
              doc.xpath("//*[namespace-uri()='']").each do |node|
                node.default_namespace = uri
              end
            else
              doc.root.add_namespace_definition(ns_prefix, uri)
            end
          end
        end
        return doc
      end
    end
  end
end
