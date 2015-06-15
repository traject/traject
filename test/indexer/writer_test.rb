require 'test_helper'
require 'traject/yaml_writer'

describe "The writer on Traject::Indexer" do
  let(:indexer) { Traject::Indexer.new("solr.url" => "http://example.com") }

  it "has a default" do
    assert_instance_of Traject::SolrJsonWriter, indexer.writer
  end

  describe "when the writer is set in config" do    
    let(:writer) { Traject::YamlWriter.new({}) }

    let(:indexer) { Traject::Indexer.new(
      "solr.url" => "http://example.com",
      "writer_class" => 'Traject::SolrJsonWriter',
      "writer"   => writer
      )}

    it "uses writer from config" do
      assert_equal writer, indexer.writer
    end

  end

  describe "when the writer is set directly" do
    let(:writer) { Traject::YamlWriter.new({}) }

    before do
      indexer.writer = writer
    end

    it "uses the set value" do
      assert_equal writer, indexer.writer
    end
  end

end
