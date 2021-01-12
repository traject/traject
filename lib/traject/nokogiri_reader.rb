require 'nokogiri'

module Traject
  # A Trajet reader which reads XML, and yields zero to many Nokogiri::XML::Document
  # objects as source records in the traject pipeline.
  #
  # It does process the entire input document with Nokogiri::XML.parse, DOM-parsing,
  # so will take RAM for the entire input document, until iteration completes.
  # (There is a separate half-finished `ExperimentalStreamingNokogiriReader` available, but it is
  # experimental, half-finished, may disappear or change in backwards compat at any time, problematic,
  # not recommended for production use, etc.)
  #
  # You can have it yield the _entire_ input XML as a single traject source record
  # (default), or you can use setting `nokogiri.each_record_xpath` to split
  # the source up into separate records to yield into traject pipeline -- each one
  # will be it's own Nokogiri::XML::Document.
  #
  # ## Settings
  # * nokogiri.default_namespaces: Set namespace prefixes that can be used in
  #   other settings, including `extract_xpath` from NokogiriMacros.
  # * nokogiri.each_record_xpath: if set to a string xpath, will take all matching nodes
  #   from the input doc, and yield the individually as source records to the pipeline.
  #   If you need to use namespaces here, you need to have them registered with
  #   `nokogiri.default_namespaces`. If your source docs use namespaces, you DO need
  #   to use them in your each_record_xpath.
  # * nokogiri.strict_mode: if set to `true` or `"true"`, ask Nokogiri to parse in 'strict'
  #   mode, it will raise a `Nokogiri::XML::SyntaxError` if the XML is not well-formed, instead
  #   of trying to take it's best-guess correction. https://nokogiri.org/tutorials/ensuring_well_formed_markup.html
  # * nokogiri_reader.extra_xpath_hooks: Experimental in progress, see below.
  #
  # ## nokogiri_reader.extra_xpath_hooks: For handling nodes outside of your each_record_xpath
  #
  # What if you want to use each_record_xpath to yield certain nodes as source documents, but
  # there is additional some other info in other parts of the input document you need? This came up
  # when developing the OaiPmhNokogiriReader, which yields "//oai:record" as pipeline source documents,
  # but also needed to look at "//oai:resumptionToken" to scrape the entire results.
  #
  # There is a semi-finished/in-progress feature that meets that use case -- unclear if it will meet
  # all use cases for this general issue.
  #
  # Setting `nokogiri_reader.extra_xpath_hooks` can be set to a Hash where the keys are xpaths (if using
  # namespaces must be must be registered with `nokogiri.default_namespaces`), and the value is a lambda/
  # proc/callable object, taking two arguments.
  #
  #     provide "nokogiri_reader.extra_xpath_hooks", {
  #       "//oai:resumptionToken" =>
  #         lambda do |node, clipboard|
  #           clipboard[:resumption_token] = node.text
  #         end"
  #     }
  #
  # The first arg is the matching node. What's this clipboard? Well, what are you
  # gonna _do_ with what you get out of there, that you can do in a thread-safe way
  # in the middle of nokogiri processing? The second arg is a thread-safe Hash "clipboard"
  # that you can store things in, and later access via reader.clipboard.
  #
  # There's no great thread-safe way to get reader.clipboard in a normal nokogiri pipeline though,
  # (the reader can change in multi-file handling so there can be a race condition if you try naively,
  # don't!) Which is why this feature needs some work for general applicability. The OaiPmhReader
  # manually creates it's readers outside the usual nokogiri flow, so can use it.
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
      config_proc = if settings["nokogiri.strict_mode"]
        proc { |config| config.strict }
      end

      whole_input_doc = Nokogiri::XML.parse(input_stream, &config_proc)

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


    # We simply do `new_parent_doc.root = node`
    # It seemed maybe safer to dup the node as well as remove the original from the original doc,
    # but I believe this will result in double memory usage, as unlinked nodes aren't GC'd until
    # their doc is.  I am hoping this pattern results in less memory usage.
    # https://github.com/sparklemotion/nokogiri/issues/1703
    #
    # We used to have to do something different in Jruby to work around bug:
    # https://github.com/sparklemotion/nokogiri/issues/1774
    #
    # But as of nokogiri 1.9, that does not work, and is not necessary if we accept
    # that Jruby nokogiri may put xmlns declerations on different elements than MRI,
    # although it should be semantically equivalent for a namespace-aware parser.
    # https://github.com/sparklemotion/nokogiri/issues/1875
    #
    # This as a separate method now exists largely as a historical artifact, and for this
    # documentation.
    def reparent_node_to_root(new_parent_doc, node)

      new_parent_doc.root = node

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
