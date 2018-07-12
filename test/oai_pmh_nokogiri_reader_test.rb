require 'test_helper'
require 'traject/oai_pmh_nokogiri_reader'

describe "Traject::OaiPmhNokogiriReader" do

  it "smoke test" do
    @reader = Traject::OaiPmhNokogiriReader.new(nil,
      "oai_pmh.start_url" => "http://example.com/oai?verb=ListRecords&metadataPrefix=oai_dc"
    )

    fetched = @reader.to_a

    assert_length 2, fetched
  end

  before do
    stub_request(:get, "http://example.com/oai?metadataPrefix=oai_dc&verb=ListRecords").
      to_return(status: 200, body: File.read(support_file_path("oai-pmh-one-record-first.xml")))

    stub_request(:get, "http://example.com/oai?resumptionToken=dummy_resumption&verb=ListRecords").
      to_return(status: 200, body: File.read(support_file_path("oai-pmh-one-record-2.xml")))
  end
end
