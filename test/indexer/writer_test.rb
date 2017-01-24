require 'test_helper'
require 'traject/yaml_writer'

describe "The writer on Traject::Indexer" do
  let(:indexer) { Traject::Indexer.new("solr.url" => "http://localhost.com") }

  # TODO: fix default writer test
  # Fails in the absence of a configured
  # network interface.
  describe "default writer from index" do
    it "has a default" do
      # assert_instance_of Traject::SolrJsonWriter, indexer.writer
      # assert_equal Traject::SolrJsonWriter, indexer.writer_class
     skip "Fails in the absence of a configured network interface."
    end
  end


  describe "when the writer is set in config" do
    let(:writer) { Traject::YamlWriter.new({}) }

    let(:indexer) { Traject::Indexer.new(
        "solr.url"     => "http://example.com",
        "writer_class" => 'Traject::SolrJsonWriter',
        "writer"       => writer
    ) }

    it "uses writer from config" do
      assert_equal writer, indexer.writer
      assert_equal writer.class, indexer.writer_class
    end
  end

  describe "when writer_class is set directly" do
    let(:writer_class) { Traject::YamlWriter }

    before do
      indexer.writer_class = writer_class
    end

    it "uses writer_class set directly" do
      assert_kind_of writer_class, indexer.writer
      assert_equal writer_class, indexer.writer_class
    end

  end

  describe "when the writer is set directly" do
    let(:writer) { Traject::YamlWriter.new({}) }

    before do
      indexer.writer = writer
    end

    it "uses the set value" do
      assert_equal writer, indexer.writer
      assert_equal writer.class, indexer.writer_class
    end
  end

end
