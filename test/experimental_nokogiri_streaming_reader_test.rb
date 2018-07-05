require 'test_helper'
require 'traject/experimental_nokogiri_streaming_reader'

# Streaming nokogiri reader is experimental, half-finished, and not supported for real use.
describe "Traject::ExperimentalNokogiriStreamingReader" do
  describe "with namespaces" do
    before do
      @namespaces = { "oai" => "http://www.openarchives.org/OAI/2.0/" }
      @xml_sample_path = support_file_path("sample-oai-pmh.xml")
    end

    describe "invalid settings" do
      it "default_namespaces not a hash raises" do
        error = assert_raises(ArgumentError) {
          @reader = Traject::ExperimentalNokogiriStreamingReader.new(File.open(@xml_sample_path), {
            "nokogiri.namespaces" => "i am not a hash",
          })
        }
        assert(error.message =~ /nokogiri.namespaces must be a hash/)
      end

      it "each_record_xpath with unregistered prefix raises" do
        error = assert_raises(ArgumentError) {
          @reader = Traject::ExperimentalNokogiriStreamingReader.new(File.open(@xml_sample_path), {
            "nokogiri.namespaces" => @namespaces,
            "nokogiri.each_record_xpath" => "//foo:bar"
          })
        }
        assert(error.message =~ %r{Can't find namespace prefix 'foo' in '//foo:bar'})
      end

      it "raises on some unsupported xpath" do
        error = assert_raises(ArgumentError) {
          @reader = Traject::ExperimentalNokogiriStreamingReader.new(File.open(@xml_sample_path), {
            "nokogiri.namespaces" => @namespaces,
            "nokogiri.each_record_xpath" => "//oai:record[@id='foo']"
          })
        }
        assert(error.message =~ /Only very simple xpaths supported\./)
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
        @reader = Traject::ExperimentalNokogiriStreamingReader.new(File.open(@xml_sample_path), {
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
        @reader = Traject::ExperimentalNokogiriStreamingReader.new(File.open(support_file_path("namespace-test.xml")), {
          "nokogiri.namespaces" => { mytop: "http://example.org/top" },
          "nokogiri.each_record_xpath" => "//mytop:record"
        })
        yielded_records = []
        @reader.each { |record|
          yielded_records << record
        }

        assert yielded_records.length > 0

        expected_namespaces = {"xmlns"=>"http://example.org/top", "xmlns:a"=>"http://example.org/a", "xmlns:b"=>"http://example.org/b"}
        yielded_records.each do |rec|
          assert_equal expected_namespaces, rec.namespaces
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


  def shared_tests
    @reader = Traject::ExperimentalNokogiriStreamingReader.new(File.open(@xml_sample_path), {
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
    assert_equal manually_extracted.collect(&:to_xml), yielded_records.collect(&:root).collect(&:to_xml)
  end

  describe "without each_record_xpath" do
    before do
      @xml_sample_path = support_file_path("namespace-test.xml")
    end
    it "yields whole file as one record" do
      @reader = Traject::ExperimentalNokogiriStreamingReader.new(File.open(@xml_sample_path), {})

      yielded_records = @reader.to_a

      assert_length 1, yielded_records
      assert_equal Nokogiri::XML.parse(File.open(@xml_sample_path)).to_xml, yielded_records.first.to_xml
    end
  end
end
