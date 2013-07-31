require 'test_helper'

require 'traject/indexer'
require 'traject/macros/marc21_semantics'

require 'json'
require 'marc/record'

# See also marc_extractor_test.rb for more detailed tests on marc extraction,
# this is just a basic test to make sure our macro works passing through to there
# and other options.
describe "Traject::Macros::Marc21Semantics" do
  Marc21Semantics = Traject::Macros::Marc21Semantics # shortcut

  before do
    @indexer = Traject::Indexer.new
    @indexer.extend Marc21Semantics

    @record = MARC::Reader.new(support_file_path  "manufacturing_consent.marc").to_a.first
  end

  it "oclcnum" do
    @indexer.instance_eval do
      to_field "oclcnum", oclcnum
    end
    output = @indexer.map_record(@record)

    assert_equal %w{2710183 47971712},  output["oclcnum"]
  end

  describe "marc_sortable_author" do
    # these probably should be taking only certain subfields, but we're copying
    # from SolrMarc that didn't do so either and nobody noticed, so not bothering for now.
    before do
      @indexer.instance_eval do
        to_field "author_sort", marc_sortable_author
      end
    end
    it "collates author and title" do
      output = @indexer.map_record(@record)

      assert_equal ["Herman, Edward S.Manufacturing consent : the political economy of the mass media / Edward S. Herman and Noam Chomsky ; with a new introduction by the authors."], output["author_sort"]
    end
    it "respects non-filing" do
      @record = MARC::Reader.new(support_file_path  "the_business_ren.marc").to_a.first

      output = @indexer.map_record(@record)

      assert_equal ["Business renaissance quarterly [electronic resource]."], output["author_sort"]
    end
  end

  describe "marc_sortable_title" do
    before do
      @indexer.instance_eval { to_field "title_sort", marc_sortable_title }
    end
    it "works" do
      output = @indexer.map_record(@record)
      assert_equal ["Manufacturing consent : the political economy of the mass media"], output["title_sort"]
    end
    it "respects non-filing" do
      @record = MARC::Reader.new(support_file_path  "the_business_ren.marc").to_a.first
      output = @indexer.map_record(@record)

      assert_equal ["Business renaissance quarterly"], output["title_sort"]
    end
  end

  describe "marc_languages" do
    before do
      @indexer.instance_eval {to_field "languages", marc_languages() }
    end

    it "unpacks packed 041a and translates" do
      @record = MARC::Reader.new(support_file_path  "packed_041a_lang.marc").to_a.first
      output = @indexer.map_record(@record)

      assert_equal ["English", "French", "German", "Italian", "Spanish", "Russian"], output["languages"]
    end
  end

  describe "marc_instrumentation_humanized" do
    before do
      @record = MARC::Reader.new(support_file_path  "musical_cage.marc").to_a.first
      @indexer.instance_eval {to_field "instrumentation", marc_instrumentation_humanized }
    end

    it "translates, de-duping" do
      output = @indexer.map_record(@record)

      assert_equal ["Larger ensemble, Unspecified", "Piano", "Soprano voice", "Tenor voice", "Violin", "Larger ensemble, Ethnic", "Guitar", "Voices, Unspecified"], output["instrumentation"]
    end
  end

  describe "marc_instrument_codes_normalized" do
    before do
      @record = MARC::Reader.new(support_file_path  "musical_cage.marc").to_a.first
      @indexer.instance_eval {to_field "instrument_codes", marc_instrument_codes_normalized }
    end
    it "normalizes, de-duping" do
      output = @indexer.map_record(@record)

      assert_equal ["on", "ka01", "ka", "va01", "va", "vd01", "vd", "sa01", "sa", "oy", "tb01", "tb", "vn12", "vn"],
        output["instrument_codes"]
    end
    it "codes soloist 048$b" do
      @record = MARC::Reader.new(support_file_path  "louis_armstrong.marc").to_a.first
      output = @indexer.map_record(@record)

      assert_equal ["bb01", "bb01.s", "bb", "bb.s", "oe"],
        output["instrument_codes"]
    end
  end

  describe "publication_date" do
    # there are way too many edge cases for us to test em all, but we'll test some of em.
    it "pulls out 008 date_type s" do
      @record = MARC::Reader.new(support_file_path  "manufacturing_consent.marc").to_a.first
      assert_equal 2002, Marc21Semantics.publication_date(@record)
    end
    it "uses start date for date_type c continuing resource" do
      @record = MARC::Reader.new(support_file_path  "the_business_ren.marc").to_a.first
      assert_equal 2006, Marc21Semantics.publication_date(@record)
    end
    it "returns nil when the records really got nothing" do
      @record = MARC::Reader.new(support_file_path  "emptyish_record.marc").to_a.first
      assert_equal nil, Marc21Semantics.publication_date(@record)
    end
    it "estimates with a single 'u'" do
      @record = MARC::Reader.new(support_file_path  "date_with_u.marc").to_a.first
      # was 184u as date1 on a continuing resource. For continuing resources,
      # we take the first date. And need to deal with the u.
      assert_equal 1845, Marc21Semantics.publication_date(@record)
    end
    it "resorts to 260c" do
      @record = MARC::Reader.new(support_file_path  "date_resort_to_260.marc").to_a.first
      assert_equal 1980, Marc21Semantics.publication_date(@record)
    end
    it "works with date type r missing date2" do
      @record = MARC::Reader.new(support_file_path  "date_type_r_missing_date2.marc").to_a.first
      assert_equal 1957, Marc21Semantics.publication_date(@record)
    end
  end

  describe "marc_lcc_to_broad_category" do
    before do
      @indexer.instance_eval {to_field "discipline_facet", marc_lcc_to_broad_category }
    end
    it "maps a simple example" do
      @record = MARC::Reader.new(support_file_path  "manufacturing_consent.marc").to_a.first
      output = @indexer.map_record(@record)

      assert_equal ["Language & Literature"], output["discipline_facet"]
    end
    it "maps to default" do
      @record = MARC::Reader.new(support_file_path  "musical_cage.marc").to_a.first
      output = @indexer.map_record(@record)
      assert_equal ["Unknown"], output["discipline_facet"]
    end
    it "maps to nothing if none and no default" do
      @indexer.instance_eval {to_field "discipline_no_default", marc_lcc_to_broad_category(:default => nil)}
      @record = MARC::Reader.new(support_file_path  "musical_cage.marc").to_a.first
      output = @indexer.map_record(@record)

      assert_nil output["discipline_no_default"]
    end
  end

  describe "marc_geo_facet" do
    before do
      @indexer.instance_eval {to_field "geo_facet", marc_geo_facet }
    end
    it "maps a complicated record" do
      @record = MARC::Reader.new(support_file_path  "multi_geo.marc").to_a.first
      output = @indexer.map_record(@record)

      assert_equal ["Europe", "Middle East", "Africa, North", "Agora (Athens, Greece)", "Rome (Italy)", "Italy"], 
        output["geo_facet"]
    end
    it "maps nothing on a record with no geo" do
      @record = MARC::Reader.new(support_file_path  "manufacturing_consent.marc").to_a.first
      output = @indexer.map_record(@record)
      assert_nil output["geo_facet"]
    end
    it "works on mysteriously failing record" do
      @record = MARC::Reader.new(support_file_path  "mysterious_bad_geo.marc").to_a.first
      output = @indexer.map_record(@record)
      assert_nil output["geo_facet"]
    end
  end

end