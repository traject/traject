module Traject
  class NokogiriReader
    include Enumerable

    attr_reader :settings, :input_stream, :clipboard, :path_tracker

    def initialize(input_stream, settings)
      @settings = Traject::Indexer::Settings.new settings
      @input_stream = input_stream
      @clipboard = Traject::Util.is_jruby? ? Concurrent::Map.new : Concurrent::Hash.new

      default_namespaces # trigger validation
      validate_xpath(each_record_xpath, key_name: "each_record_xpath") if each_record_xpath
      extra_xpath_hooks.each_pair do |xpath, _callable|
        validate_xpath(xpath, key_name: "extra_xpath_hooks")
      end
    end

    def each_record_xpath
      @each_record_xpath ||= settings["nokogiri.each_record_xpath"]
    end

    def extra_xpath_hooks
      @extra_xpath_hooks ||= settings["nokogiri_reader.extra_xpath_hooks"] || {}
    end

    def default_namespaces
      @default_namespaces ||= (settings["nokogiri.namespaces"] || {}).tap { |ns|
        unless ns.kind_of?(Hash)
          raise ArgumentError, "nokogiri.namespaces must be a hash, not: #{ns.inspect}"
        end
      }
    end

    def each
      whole_input_doc = Nokogiri::XML.parse(input_stream)

      if each_record_xpath
        whole_input_doc.xpath(each_record_xpath, default_namespaces).each do |matching_node|
          # We want to take the matching node, and make it into root in a new Nokogiri document.
          # This is tricky to do as performant as possible (we want to re-use the existing libxml node),
          # while preserving namespaces properly (especially in jruby). Some uses of noko api that seem
          # like they should work don't, esp in jruby.
          child_doc = Nokogiri::XML::Document.new

          reparent_node_to_root(child_doc, matching_node)

          yield child_doc

          child_doc = nil # hopefully make things easier on the GC.
        end
      else
        # caller wants whole doc as a traject source record
        yield whole_input_doc
      end

      run_extra_xpath_hooks(whole_input_doc)

    ensure
      # hopefully make things easier on the GC.
      whole_input_doc = nil
    end

    private


    # In MRI Nokogiri, this is as simple as `new_parent_doc.root = node`
    # It seemed maybe safer to dup the node as well as remove the original from the original doc,
    # but I believe this will result in double memory usage, as unlinked nodes aren't GC'd until
    # their doc is.  I am hoping this pattern results in less memory usage.
    # https://github.com/sparklemotion/nokogiri/issues/1703
    #
    # However, in JRuby it's a different story, JRuby doesn't properly preserve namespaces
    # when re-parenting a node.
    # https://github.com/sparklemotion/nokogiri/issues/1774
    #
    # The nodes within the tree re-parented _know_ they are in the correct namespaces,
    # and xpath queries require that namespace, but the appropriate xmlns attributes
    # aren't included in the serialized XML. This JRuby-specific code seems to get
    # things back to a consistent state.
    def reparent_node_to_root(new_parent_doc, node)
      if Traject::Util.is_jruby?
        original_ns_scopes = node.namespace_scopes
      end

      new_parent_doc.root = node

      if Traject::Util.is_jruby?
        original_ns_scopes.each do |ns|
          if new_parent_doc.at_xpath("//#{ns.prefix}:*", ns.prefix => ns.href)
            new_parent_doc.root.add_namespace(ns.prefix, ns.href)
          end
        end
      end

      return new_parent_doc
    end

    def validate_xpath(xpath, key_name:)
      components = each_record_xpath.split('/')
      components.each do |component|
        prefix, element = component.split(':')
        unless element
          # there was no namespace
          prefix, element = nil, prefix
        end

        if prefix
          ns_uri = default_namespaces[prefix]
          if ns_uri.nil?
            raise ArgumentError, "#{key_name}: Can't find namespace prefix '#{prefix}' in '#{each_record_xpath}'. To use a namespace in each_record_xpath, it has to be registered with nokogiri.namespaces: #{default_namespaces.inspect}"
          end
        end
      end
    end

    def run_extra_xpath_hooks(noko_doc)
      extra_xpath_hooks.each_pair do |xpath, callable|
        noko_doc.xpath(xpath, default_namespaces).each do |matching_node|
          callable.call(matching_node, clipboard)
        end
      end
    end
  end
end
