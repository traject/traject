require 'test_helper'

describe "Traject::NokogiriIndexer" do
  before do
    Traject::Indexer.send(:default_settings=, Traject::Indexer.default_settings.merge("solr_writer.thread_pool" => 0, "processing_thread_pool" => 0))


    @xml_sample_path = support_file_path("sample-oai-pmh.xml")
    @indexer = Traject::Indexer::NokogiriIndexer.new("writer_class_name" => "Traject::ArrayWriter", "solr_writer.thread_pool" => 0, "processing_thread_pool" => 0)
    @namespaces = {
      "oai" => "http://www.openarchives.org/OAI/2.0/",
      "dc" => "http://purl.org/dc/elements/1.1/",
      "oai_dc" => "http://www.openarchives.org/OAI/2.0/oai_dc/",
      "edm" => "http://www.europeana.eu/schemas/edm/"
    }
  end

  it "smoke test" do
    namespaces = @namespaces
    @indexer.configure do
      settings do
        provide "nokogiri.namespaces", namespaces
        provide "nokogiri.each_record_xpath", "//oai:record"
      end
      to_field "id", extract_xpath("//oai:metadata/oai_dc:dc/dc:identifier"), first_only
      to_field "title", extract_xpath("//oai:metadata/oai_dc:dc/dc:title")
    end

    @indexer.process(File.open(@xml_sample_path))

    results = @indexer.writer.values

    source_doc = Nokogiri::XML.parse(File.open(@xml_sample_path))

    assert_equal source_doc.xpath("//oai:record", @namespaces).count, results.count
    assert(results.all? { |hash|
      hash["id"] && hash["id"].length == 1 &&
      hash["title"] && hash["title"].length >= 1
    }, "expected results have expected values")
  end

  it "namespaces to extract_xpath" do
    namespaces = @namespaces.merge(edm: "http://this.is.wrong")
    @indexer.configure do
      settings do
        provide "nokogiri.namespaces", namespaces
        provide "nokogiri.each_record_xpath", "//oai:record"
      end
      to_field "rights", extract_xpath("//oai:metadata/oai_dc:dc/edm:rights", ns: { edm: "http://www.europeana.eu/schemas/edm/" })
    end

    @indexer.process(File.open(@xml_sample_path))

    results = @indexer.writer.values

    refute_empty results.last["rights"]
  end

  it "exposes nokogiri.namespaces setting in default_namespaces" do
    namespaces = @namespaces
    @indexer.configure do
      settings do
        provide "nokogiri.namespaces", namespaces
      end
    end
    @indexer.settings.fill_in_defaults!
    assert_equal namespaces, @indexer.default_namespaces
  end

  describe "xpath to non-terminal element" do
    before do
      @xml = <<-EOS
      <record>
        <name>
          <first>José</first>
          <last>Lopez</last>
        </name>
        <name>
          <first>Sue</first>
          <last>Jones</last>
        </name>
      </record>
      EOS

      @indexer.configure do
        settings do
          provide "nokogiri.each_record_xpath", "//record"
        end
      end
    end

    it "outputs text" do
      @indexer.configure { to_field "name", extract_xpath("/record/name") }
      @indexer.process(StringIO.new(@xml))
      results = @indexer.writer.values

      assert_equal( {"name" => ["José Lopez", "Sue Jones"]}, results.first )
    end

    it "outputs Nokogiri::XML::Element with to_text: false" do
      @indexer.configure { to_field "name", extract_xpath("/record/name", to_text: false) }
      @indexer.process(StringIO.new(@xml))
      results = @indexer.writer.values

      values = results.first["name"]

      assert(values.each { |result|
        result["name"].kind_of?(Nokogiri::XML::Element) &&
        result["name"].name == "name"
      })
    end
  end

  describe "xpath to attribute" do
    let(:indexer) do
      namespaces = @namespaces
      Traject::Indexer::NokogiriIndexer.new("nokogiri.namespaces" => namespaces,
                                            "nokogiri.each_record_xpath" => "//oai:record") do
        to_field "status", extract_xpath("//oai:record/oai:header/@status")
      end
    end

    let(:records) { Traject::NokogiriReader.new(StringIO.new(
                                                      <<-XML
      <?xml version="1.0" encoding="UTF-8"?>
      <OAI-PMH xmlns="http://www.openarchives.org/OAI/2.0/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd">
        <responseDate>2020-03-03T04:16:09Z</responseDate>
        <request verb="ListRecords" metadataPrefix="marc21" set="blacklight" from="2020-03-02T20:47:11Z">https://na02.alma.exlibrisgroup.com/view/oai/01TULI_INST/request</request>
        <ListRecords>
          <record>
            <header status="deleted">
              <identifier>oai:alma.01TULI_INST:991025803889703811</identifier>
              <datestamp>2020-03-03T03:54:35Z</datestamp>
              <setSpec>blacklight</setSpec>
              <setSpec>rapid_print_journals</setSpec>
              <setSpec>blacklight_qa</setSpec>
            </header>
          </record>
        </ListRecords>
      </OAI-PMH>
          XML
    ), []).to_a }

    it "extracts the correct attribute" do
      statuses = indexer.map_record(records.first)["status"]
      assert_equal ["deleted"], statuses
    end
  end
end
