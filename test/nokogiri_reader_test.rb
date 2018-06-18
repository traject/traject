require 'test_helper'
require 'traject/nokogiri_reader'

describe "Traject::NokogiriReader" do

  def shared_tests
    @reader = Traject::NokogiriReader.new(File.open(@xml_sample_path), {
      "nokogiri_reader.default_namespaces" => @namespaces,
      "nokogiri_reader.each_record_xpath" => @each_record_xpath
    })

    yielded_records = []
    @reader.each { |record|
      yielded_records << record
    }


    manually_extracted = Nokogiri::XML.parse(File.open(@xml_sample_path)).xpath(@each_record_xpath, @namespaces)
    # crazy hack, oh Nokogiri namespaces
    manually_extracted.collect do |node|
      node["xmlns"] = node.namespace.href if node.namespace
    end

    assert_length manually_extracted.size, yielded_records
    assert yielded_records.all? {|r| r.kind_of? Nokogiri::XML::Document }

    assert_equal manually_extracted.collect(&:to_xml), yielded_records.collect(&:root).collect(&:to_xml)
  end

  describe "with namespaces" do
    before do
      @namespaces = { "oai" => "http://www.openarchives.org/OAI/2.0/" }
      @xml_sample_path = support_file_path("sample-oai-pmh.xml")
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
end
