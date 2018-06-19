require 'test_helper'

describe "Traject::NokogiriIndexer" do
  before do
    @xml_sample_path = support_file_path("sample-oai-pmh.xml")
    @indexer = Traject::Indexer::NokogiriIndexer.new("writer_class_name" => "Traject::ArrayWriter")
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
        provide "nokogiri_reader.default_namespaces", namespaces
        provide "nokogiri_reader.each_record_xpath", "//oai:record"
      end
      to_field "id", extract_xpath("//oai:metadata/oai_dc:dc/dc:identifier"), first_only
      to_field "title", extract_xpath("//oai:metadata/oai_dc:dc/dc:title")
      to_field "rights", extract_xpath("//oai:metadata/oai_dc:dc/edm:rights")
    end

    @indexer.process(File.open(@xml_sample_path))

    results = @indexer.writer.values

    source_doc = Nokogiri::XML.parse(File.open(@xml_sample_path))

    assert_equal source_doc.xpath("//oai:record", @namespaces).count, results.count
    assert(results.all? { |hash|
      hash["id"].length == 1 &&
      hash["title"].length >= 1
    })
  end
end
