module Traject
  # An EXPERIMENTAL HALF-FINISHED implementation of a streaming/pull reader using Nokogiri.
  # Not ready for use, not stable API, could go away.
  #
  # This was my first try at a NokogiriReader implementation, it didn't work out, at least without
  # a lot more work. I think we'd need to re-do it to build the Nokogiri::XML::Nodes by hand as the
  # source is traversed, instead of relying on #outer_xml -- outer_xml returning a string results in a double-parsing,
  # with the expected 50% performance hit.  Picadillos in Nokogiri JRuby namespace handling don't help.
  #
  # All in all, it's possible something could be gotten here with a lot more work, it's also possible
  # Nokogiri's antipathy to namespaces could keep getting in the way.
  class ExperimentalNokogiriStreamingReader
    include Enumerable

    attr_reader :settings, :input_stream, :clipboard, :path_tracker

    def initialize(input_stream, settings)
      @settings = Traject::Indexer::Settings.new settings
      @input_stream = input_stream
      @clipboard = Traject::Util.is_jruby? ? Concurrent::Map.new : Concurrent::Hash.new

      if each_record_xpath
        @path_tracker = PathTracker.new(each_record_xpath,
                                          clipboard: self.clipboard,
                                          namespaces: default_namespaces,
                                          extra_xpath_hooks: extra_xpath_hooks)
      end

      default_namespaces # trigger validation
      validate_limited_xpath(each_record_xpath, key_name: "each_record_xpath")

    end

    def each_record_xpath
      @each_record_xpath ||= settings["nokogiri.each_record_xpath"]
    end

    def extra_xpath_hooks
      @extra_xpath_hooks ||= begin
        (settings["nokogiri_reader.extra_xpath_hooks"] || {}).tap do |hash|
          hash.each_pair do |limited_xpath, callable|
            validate_limited_xpath(limited_xpath, key_name: "nokogiri_reader.extra_xpath_hooks")
          end
        end
      end
    end

    protected def validate_limited_xpath(each_record_xpath, key_name:)
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
          raise ArgumentError, "#{key_name}: Only very simple xpaths supported. '//some/path' or '/some/path'. Not: #{each_record_xpath.inspect}"
        end

        if prefix
          ns_uri = default_namespaces[prefix]
          if ns_uri.nil?
            raise ArgumentError, "each_record_xpath: Can't find namespace prefix '#{prefix}' in '#{each_record_xpath}'. To use a namespace in each_record_xpath, it has to be registered with nokogiri.namespaces: #{default_namespaces.inspect}"
          end
        end
      end

      each_record_xpath
    end


    def default_namespaces
      @default_namespaces ||= (settings["nokogiri.namespaces"] || {}).tap { |ns|
        unless ns.kind_of?(Hash)
          raise ArgumentError, "nokogiri.namespaces must be a hash, not: #{ns.inspect}"
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
            yield path_tracker.current_node_doc
          end
          path_tracker.run_extra_xpath_hooks

          if reader_node.self_closing?
            path_tracker.pop
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
    # they are registered with settings nokogiri.namespaces
    #
    # sadly JRuby Nokogiri has an incompatibility with true nokogiri, and
    # doesn't preserve our namespaces on outer_xml,
    # so in JRuby we have to track them ourselves, and then also do yet ANOTHER
    # parse in nokogiri. This may make this in Java even LESS performant, I'm afraid.
    class PathTracker
      attr_reader :path_spec, :inverted_namespaces, :current_path, :namespaces_stack, :extra_xpath_hooks, :clipboard
      def initialize(str_spec, clipboard:, namespaces: {}, extra_xpath_hooks: {})
        @inverted_namespaces  = namespaces.invert
        @clipboard = clipboard
        # We're guessing using a string will be more efficient than an array
        @current_path         = ""
        @floating             = false

        @path_spec, @floating = parse_path(str_spec)

        @namespaces_stack = []


        @extra_xpath_hooks = extra_xpath_hooks.collect do |path, callable|
          bare_path, floating = parse_path(path)
          {
            path: bare_path,
            floating: floating,
            callable: callable
          }
        end
      end

      # returns [bare_path, is_floating]
      protected def parse_path(str_spec)
        floating = false

        if str_spec.start_with?('//')
          str_spec = str_spec.slice(2..-1)
          floating = true
        else
          str_spec = str_spec.slice(1..-1) if str_spec.start_with?(".")
          str_spec = "/" + str_spec unless str_spec.start_with?("/")
        end

        return [str_spec, floating]
      end

      def is_jruby?
        Traject::Util.is_jruby?
      end

      # adds a component to slash-separated current_path, with namespace prefix.
      def push(reader_node)
        namespace_prefix = reader_node.namespace_uri && inverted_namespaces[reader_node.namespace_uri]

        # gah, reader_node.name has the namespace prefix in there
        node_name = reader_node.name.gsub(/[^:]+:/, '')

        node_str = if namespace_prefix
          namespace_prefix + ":" + node_name
        else
          reader_node.name
        end

        current_path << ("/" + node_str)

        if is_jruby?
          namespaces_stack << reader_node.namespaces
        end
        @current_node = reader_node
      end

      def current_node_doc
        return nil unless @current_node

        # yeah, sadly we got to have nokogiri parse it again
        fix_namespaces(Nokogiri::XML.parse(@current_node.outer_xml))
      end

      # removes the last slash-separated component from current_path
      def pop
        current_path.slice!( current_path.rindex('/')..-1 )
        @current_node = nil

        if is_jruby?
          namespaces_stack.pop
        end
      end

      def floating?
        !!@floating
      end

      def match?
        match_path?(path_spec, floating: floating?)
      end

      def match_path?(path_to_match, floating:)
        if floating?
          current_path.end_with?(path_to_match)
        else
          current_path == path_to_match
        end
      end

      def run_extra_xpath_hooks
        return unless @current_node

        extra_xpath_hooks.each do |hook_spec|
          if match_path?(hook_spec[:path], floating: hook_spec[:floating])
            hook_spec[:callable].call(current_node_doc, clipboard)
          end
        end
      end

      # no-op unless it's jruby, and then we use our namespace stack to
      # correctly add namespaces to the Nokogiri::XML::Document, cause
      # in Jruby outer_xml on the Reader doesn't do it for us. :(
      def fix_namespaces(doc)
        if is_jruby?
          # Only needed in jruby, nokogiri's jruby implementation isn't weird
          # around namespaces in exactly the same way as MRI. We need to keep
          # track of the namespaces in outer contexts ourselves, and then see
          # if they are needed ourselves. :(
          namespaces = namespaces_stack.compact.reduce({}, :merge)
          default_ns = namespaces.delete("xmlns")

          namespaces.each_pair do |attrib, uri|
            ns_prefix = attrib.sub(/\Axmlns:/, '')

            # gotta make sure it's actually used in the doc to not add it
            # unecessarily. GAH.
            if    doc.xpath("//*[starts-with(name(), '#{ns_prefix}:')][1]").empty? &&
                  doc.xpath("//@*[starts-with(name(), '#{ns_prefix}:')][1]").empty?
              next
            end
            doc.root.add_namespace_definition(ns_prefix, uri)
          end

          if default_ns
            doc.root.default_namespace = default_ns
            # OMG nokogiri, really?
            default_ns = doc.root.namespace
            doc.xpath("//*[namespace-uri()='']").each do |node|
              node.namespace = default_ns
            end
          end

        end
        return doc
      end
    end
  end
end
