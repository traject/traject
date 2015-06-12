require 'test_helper'
require 'traject/yaml_writer'

describe "The writer on Traject::Indexer" do
  let(:indexer) { Traject::Indexer.new("solr.url" => "http://example.com") }

  it "has a default" do
    assert_instance_of Traject::SolrJsonWriter, indexer.writer
  end

  describe "when the writer is set" do
    let(:writer) { Traject::YamlWriter.new({}) }

    before do
      indexer.writer = writer
    end

    it "uses the set value" do
      assert_equal writer, indexer.writer
    end
  end

end
