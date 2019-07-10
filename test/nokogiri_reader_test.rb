require 'test_helper'
require 'traject/nokogiri_reader'

# Note that JRuby Nokogiri can treat namespaces differently than MRI nokogiri.
# Particularly when we extract elements from a larger document with `each_record_xpath`,
# and put them in their own document, in JRuby nokogiri the xmlns declarations
# can end up on different elements than expected, although the document should
# be semantically equivalent to an XML-namespace-aware processor. See:
# https://github.com/sparklemotion/nokogiri/issues/1875
describe "Traject::NokogiriReader" do
  describe "with namespaces" do
    before do
      @namespaces = { "oai" => "http://www.openarchives.org/OAI/2.0/" }
      @xml_sample_path = support_file_path("sample-oai-pmh.xml")
    end

    describe "invalid settings" do
      it "default_namespaces not a hash raises" do
        error = assert_raises(ArgumentError) {
          @reader = Traject::NokogiriReader.new(File.open(@xml_sample_path), {
            "nokogiri.namespaces" => "i am not a hash",
          })
        }
        assert(error.message =~ /nokogiri.namespaces must be a hash/)
      end

      it "each_record_xpath with unregistered prefix raises" do
        error = assert_raises(ArgumentError) {
          @reader = Traject::NokogiriReader.new(File.open(@xml_sample_path), {
            "nokogiri.namespaces" => @namespaces,
            "nokogiri.each_record_xpath" => "//foo:bar"
          })
        }
        assert(error.message =~ %r{Can't find namespace prefix 'foo' in '//foo:bar'})
      end
    end

    describe "fixed path" do
      before do
        @each_record_xpath = "/oai:OAI-PMH/oai:ListRecords/oai:record"
      end

      it "reads" do
        shared_tests
      end
    end

    describe "floating path" do
      before do
        @each_record_xpath = "//oai:record"
      end

      it "reads" do
        shared_tests
      end
    end


    describe "extra_xpath_hooks" do
      it "catches oai-pmh resumption token" do
        @reader = Traject::NokogiriReader.new(File.open(@xml_sample_path), {
          "nokogiri.namespaces" => @namespaces,
          "nokogiri.each_record_xpath" => "//oai:record",
          "nokogiri_reader.extra_xpath_hooks" => {
            "//oai:resumptionToken" => lambda do |node, clipboard|
              clipboard[:resumptionToken] = node.text
            end
          }
        })
        _records = @reader.to_a
        assert_equal "oai_dc.f(2018-05-03T18:09:08Z).u(2018-06-15T19:25:21Z).t(6387):100", @reader.clipboard[:resumptionToken]
      end
    end

    describe "outer namespaces" do
      it "are preserved" do
        @reader = Traject::NokogiriReader.new(File.open(support_file_path("namespace-test.xml")), {
          "nokogiri.namespaces" => { mytop: "http://example.org/top" },
          "nokogiri.each_record_xpath" => "//mytop:record"
        })
        yielded_records = []
        @reader.each { |record|
          yielded_records << record
        }

        assert yielded_records.length > 0

        expected_namespaces = {"xmlns"=>"http://example.org/top", "xmlns:a"=>"http://example.org/a", "xmlns:b"=>"http://example.org/b"}

        if !Traject::Util.is_jruby?
          yielded_records.each do |rec|
            assert_equal expected_namespaces, rec.namespaces
          end
        else
          # jruby nokogiri shuffles things around, all we can really do is test that the namespaces
          # are somehwere in the doc :( We rely on other tests to test semantic equivalence.
          yielded_records.each do |rec|
            assert_equal expected_namespaces, rec.collect_namespaces
          end

          whole_doc = Nokogiri::XML.parse(File.open(support_file_path("namespace-test.xml")))
          whole_doc.xpath("//mytop:record", mytop: "http://example.org/top").each_with_index do |original_el, i|
            assert ns_semantic_equivalent_xml?(original_el, yielded_records[i])
          end
        end
      end
    end
  end

  describe "without namespaces" do
    before do
      @namespaces = {}
      @xml_sample_path = support_file_path("sample-oai-no-namespace.xml")
    end

    describe "fixed path" do
      before do
        @each_record_xpath = "/OAI-PMH/ListRecords/record"
      end

      it "reads" do
        shared_tests
      end
    end

    describe "floating path" do
      before do
        @each_record_xpath = "//record"
      end

      it "reads" do
        shared_tests
      end
    end
  end

  describe "strict_mode" do
    it "raises on non-well-formed" do
      # invalid because two sibling root nodes, XML requiers one root node
      reader = Traject::NokogiriReader.new(StringIO.new("<doc></doc><doc></doc>"), {"nokogiri.strict_mode" => "true" })
      assert_raises(Nokogiri::XML::SyntaxError) {
        reader.each { |r| }
      }
    end
  end


  def shared_tests
    @reader = Traject::NokogiriReader.new(File.open(@xml_sample_path), {
      "nokogiri.namespaces" => @namespaces,
      "nokogiri.each_record_xpath" => @each_record_xpath
    })

    yielded_records = []
    @reader.each { |record|
      yielded_records << record
    }


    manually_extracted = Nokogiri::XML.parse(File.open(@xml_sample_path)).xpath(@each_record_xpath, @namespaces)
    manually_extracted.collect do |node|
      # nokogiri makes it so hard to reliably get an Element to serialize to XML with all
      # it's inherited namespace declerations. :(  We're only doing this for testing purposes
      # anyway.  This may not handle everything, but handles what we need in the test right now
      if node.namespace
        node["xmlns"] = node.namespace.href
      end
    end

    assert_length manually_extracted.size, yielded_records
    assert yielded_records.all? {|r| r.kind_of? Nokogiri::XML::Document }

    expected_xml = manually_extracted
    actual_xml   = yielded_records.collect(&:root)

    expected_xml.size.times do |i|
      if !Traject::Util.is_jruby?
        assert_equal expected_xml[i-1].to_xml, actual_xml[i-1].to_xml
      else
        # jruby shuffles the xmlns declarations around, but they should
        # be semantically equivalent to an namespace-aware processor
        assert ns_semantic_equivalent_xml?(expected_xml[i-1], actual_xml[i-1])
      end
    end
  end

  # Jruby nokogiri can shuffle around where the `xmlns:ns` declarations appear, although it
  # _ought_ not to be semantically different for a namespace-aware parser -- nodes are still in
  # same namespaces.  JRuby may differ from what MRI does with same code, and may differ from
  # the way an element appeared in input when extracting records from a larger input doc.
  # There isn't much we can do about this, but we can write a recursive method
  # that hopefully compares XML to make sure it really is semantically equivalent to
  # a namespace, and hope we got that right.
  def ns_semantic_equivalent_xml?(noko_a, noko_b)
    noko_a = noko_a.root if noko_a.kind_of?(Nokogiri::XML::Document)
    noko_b = noko_b.root if noko_b.kind_of?(Nokogiri::XML::Document)

    noko_a.name == noko_b.name &&
      noko_a.namespace&.prefix == noko_b.namespace&.prefix &&
      noko_a.namespace&.href   == noko_b.namespace&.href &&
      noko_a.attributes        == noko_b.attributes &&
      noko_a.children.length   == noko_b.children.length &&
      noko_a.children.each_with_index.all? do |a_child, index|
        ns_semantic_equivalent_xml?(a_child, noko_b.children[index])
      end
  end

  describe "without each_record_xpath" do
    before do
      @xml_sample_path = support_file_path("namespace-test.xml")
    end
    it "yields whole file as one record" do
      @reader = Traject::NokogiriReader.new(File.open(@xml_sample_path), {})

      yielded_records = @reader.to_a

      assert_length 1, yielded_records
      assert_equal Nokogiri::XML.parse(File.open(@xml_sample_path)).to_xml, yielded_records.first.to_xml
    end
  end
end
