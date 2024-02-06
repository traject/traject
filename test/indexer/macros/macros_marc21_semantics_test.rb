# Encoding: UTF-8

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
    @indexer.configure do
      to_field "oclcnum", oclcnum
    end
    output = @indexer.map_record(@record)

    assert_equal %w{47971712},  output["oclcnum"]

    assert_equal({}, @indexer.map_record(empty_record))
  end

  it "deals with all prefixed OCLC nunbers" do
    @record.append(MARC::DataField.new('035', ' ', ' ', ['a', '(OCoLC)ocm111111111']))
    @record.append(MARC::DataField.new('035', ' ', ' ', ['a', '(OCoLC)222222222']))
    @record.append(MARC::DataField.new('035', ' ', ' ', ['a', 'ocm333333333']))
    @record.append(MARC::DataField.new('035', ' ', ' ', ['a', 'ocn444444444']))
    @record.append(MARC::DataField.new('035', ' ', ' ', ['a', '(OCoLC)ocn555555555']))
    @record.append(MARC::DataField.new('035', ' ', ' ', ['a', '(OCoLC)on666666666']))
    @record.append(MARC::DataField.new('035', ' ', ' ', ['a', '777777777'])) # not OCLC number

    @indexer.configure do
      to_field "oclcnum", oclcnum
    end
    output = @indexer.map_record(@record)

    assert_equal %w{47971712 111111111 222222222 333333333 444444444 555555555 666666666},  output["oclcnum"]
  end



  it "#marc_series_facet" do
    @record = MARC::Reader.new(support_file_path  "louis_armstrong.marc").to_a.first

    @indexer.configure do
      to_field "series_facet", marc_series_facet
    end
    output = @indexer.map_record(@record)

    # trims punctuation too
    assert_equal ["Big bands"], output["series_facet"]
    assert_equal({}, @indexer.map_record(empty_record))

  end

  describe "marc_sortable_author" do
    # these probably should be taking only certain subfields, but we're copying
    # from SolrMarc that didn't do so either and nobody noticed, so not bothering for now.
    before do
      @indexer.configure do
        to_field "author_sort", marc_sortable_author
      end
    end
    it "collates author and title" do
      output = @indexer.map_record(@record)

      assert_equal ["Herman, Edward S.   Manufacturing consent the political economy of the mass media Edward S. Herman and Noam Chomsky ; with a new introduction by the authors"], output["author_sort"]
      assert_equal [""], @indexer.map_record(empty_record)['author_sort']

    end
    it "respects non-filing" do
      @record = MARC::Reader.new(support_file_path  "the_business_ren.marc").to_a.first

      output = @indexer.map_record(@record)

      assert_equal ["Business renaissance quarterly [electronic resource]."], output["author_sort"]
      assert_equal [""], @indexer.map_record(empty_record)['author_sort']
    end


  end

  describe "marc_sortable_title" do
    before do
      @indexer.configure { to_field "title_sort", marc_sortable_title }
    end
    it "works" do
      output = @indexer.map_record(@record)
      assert_equal ["Manufacturing consent : the political economy of the mass media"], output["title_sort"]
      assert_equal({}, @indexer.map_record(empty_record))

    end
    it "respects non-filing" do
      @record = MARC::Reader.new(support_file_path  "the_business_ren.marc").to_a.first
      output = @indexer.map_record(@record)

      assert_equal ["Business renaissance quarterly"], output["title_sort"]
    end

    it "respects non-filing when the first subfield isn't alphabetic" do
      @record = MARC::Reader.new(support_file_path  "the_business_ren.marc").first
      @record.fields("245").first.subfields.unshift MARC::Subfield.new("6", "245-03")
      output = @indexer.map_record(@record)
      assert_equal ["Business renaissance quarterly"], output["title_sort"]


    end

    it "works with a record with no 245$ab" do
      @record = MARC::Reader.new(support_file_path  "245_no_ab.marc").to_a.first
      output = @indexer.map_record(@record)
      assert_equal ["Papers"], output["title_sort"]
    end
  end

  describe "marc_languages" do
    before do
      @indexer.configure {to_field "languages", marc_languages() }
    end

    it "unpacks packed 041a and translates" do
      @record = MARC::Reader.new(support_file_path  "packed_041a_lang.marc").to_a.first
      output = @indexer.map_record(@record)

      assert_equal ["English", "French", "German", "Italian", "Spanish", "Russian"], output["languages"]
      assert_equal({}, @indexer.map_record(empty_record))

    end
    it "can handle ISO 639-3 language codes" do
      @record = MARC::Reader.new(support_file_path  "iso639-3_lang.marc").to_a.first
      output = @indexer.map_record(@record)

      assert_equal ["Norwegian", "English", "Norwegian (Bokmål)"], output["languages"]
      assert_equal({}, @indexer.map_record(empty_record))

    end
  end

  describe "marc_instrumentation_humanized" do
    before do
      @record = MARC::Reader.new(support_file_path  "musical_cage.marc").to_a.first
      @indexer.configure {to_field "instrumentation", marc_instrumentation_humanized }
    end

    it "translates, de-duping" do
      output = @indexer.map_record(@record)

      assert_equal ["Larger ensemble, Unspecified", "Piano", "Soprano voice", "Tenor voice", "Violin", "Larger ensemble, Ethnic", "Guitar", "Voices, Unspecified"], output["instrumentation"]
      assert_equal({}, @indexer.map_record(empty_record))

    end
  end

  describe "marc_instrument_codes_normalized" do
    before do
      @record = MARC::Reader.new(support_file_path  "musical_cage.marc").to_a.first
      @indexer.configure {to_field "instrument_codes", marc_instrument_codes_normalized }
    end
    it "normalizes, de-duping" do
      output = @indexer.map_record(@record)

      assert_equal ["on", "ka01", "ka", "va01", "va", "vd01", "vd", "sa01", "sa", "oy", "tb01", "tb", "vn12", "vn"],
        output["instrument_codes"]
    end
    it "codes soloist 048$b" do
      @record = MARC::Reader.new(support_file_path  "louis_armstrong.marc").to_a.first
      output = @indexer.map_record(@record)

      assert_equal ["bb01", "bb01.s", "bb", "bb.s", "oe"], output["instrument_codes"]
      assert_equal({}, @indexer.map_record(empty_record))

    end
  end

  describe "publication_date" do
    # there are way too many edge cases for us to test em all, but we'll test some of em.

    it "works when there's no date information" do
      assert_nil Marc21Semantics.publication_date(empty_record)
    end

    it "uses macro correctly with no date info" do
      @indexer.configure {to_field "date", marc_publication_date }
      assert_equal({}, @indexer.map_record(empty_record))
    end


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
      assert_nil Marc21Semantics.publication_date(@record)
    end
    it "estimates with a single 'u'" do
      @record = MARC::Reader.new(support_file_path  "date_with_u.marc").to_a.first
      # was 184u as date1 on a continuing resource. For continuing resources,
      # we take the first date. And need to deal with the u.
      assert_equal 1845, Marc21Semantics.publication_date(@record)
    end
    it "resorts to 264c" do
      @record = MARC::Reader.new(support_file_path  "date_resort_to_264.marc").to_a.first
      assert_equal 2015, Marc21Semantics.publication_date(@record)
    end
    it "resorts to 260c" do
      @record = MARC::Reader.new(support_file_path  "date_resort_to_260.marc").to_a.first
      assert_equal 1980, Marc21Semantics.publication_date(@record)
    end
    it "works with date type r missing date2" do
      @record = MARC::Reader.new(support_file_path  "date_type_r_missing_date2.marc").to_a.first
      assert_equal 1957, Marc21Semantics.publication_date(@record)
    end
    it "provides a fallback for a missing second date" do
      @record = MARC::Reader.new(support_file_path  "missing-second-date.marc").to_a.first
      assert_equal 1678, Marc21Semantics.publication_date(@record)
    end

    it "works correctly with date type 'q'" do
      val = @record['008'].value
      val[6] = 'q'
      val[7..10] = '191u'
      val[11..14] = '192u'
      @record['008'].value = val

      # Date should be date1 + date2 / 2 = (1910 + 1929) / 2 = 1919
      estimate_tolerance = 30
      assert_equal 1919, Marc21Semantics.publication_date(@record, estimate_tolerance)
    end
  end

  describe "marc_lcc_to_broad_category" do
    before do
      @indexer.configure { to_field "discipline_facet", marc_lcc_to_broad_category }
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
      assert_equal(["Unknown"], @indexer.map_record(empty_record)['discipline_facet'])
    end

    it "maps to nothing if none and no default" do
      @indexer.configure { to_field "discipline_no_default", marc_lcc_to_broad_category(:default => nil) }
      @record = MARC::Reader.new(support_file_path  "musical_cage.marc").to_a.first
      output = @indexer.map_record(@record)

      assert_nil output["discipline_no_default"]

      assert_nil @indexer.map_record(empty_record)["discipline_no_default"]

    end

    describe "LCC_REGEX" do
      it "rejects a non-LCC" do
        refute_match Traject::Macros::Marc21Semantics::LCC_REGEX, "Film no. A .N285"
      end
    end

  end

  describe "marc_geo_facet" do
    before do
      @indexer.configure { to_field "geo_facet", marc_geo_facet }
    end
    it "maps a complicated record" do
      @record = MARC::Reader.new(support_file_path  "multi_geo.marc").to_a.first
      output = @indexer.map_record(@record)

      assert_equal ["Europe", "Middle East", "Africa, North", "Agora (Athens, Greece)", "Rome (Italy)", "Italy"], output["geo_facet"]
      assert_equal({}, @indexer.map_record(empty_record))
    end
    it "maps nothing on a record with no geo" do
      @record = MARC::Reader.new(support_file_path  "manufacturing_consent.marc").to_a.first
      output = @indexer.map_record(@record)
      assert_nil output["geo_facet"]
      assert_equal({}, @indexer.map_record(empty_record))

    end
  end

  describe "marc_era_facet" do
    before do
      @indexer.configure { to_field "era_facet", marc_era_facet }
    end
    it "maps a complicated record" do
      @record = MARC::Reader.new(support_file_path  "multi_era.marc").to_a.first
      output = @indexer.map_record(@record)

      assert_equal ["Early modern, 1500-1700", "17th century", "Great Britain: Puritan Revolution, 1642-1660", "Great Britain: Civil War, 1642-1649", "1642-1660"],
        output["era_facet"]
      assert_equal({}, @indexer.map_record(empty_record))

    end
  end

  describe "marc_lcsh_display" do
    it "formats typical field" do
      field = MARC::DataField.new('650', ' ', ' ', ['a', 'Psychoanalysis and literature'], ['z', 'England'], ['x', 'History'], ['y', '19th century.'])
      str = Marc21Semantics.assemble_lcsh(field)

      assert_equal "Psychoanalysis and literature — England — History — 19th century", str

    end

    it "ignores numeric subfields" do
      field = MARC::DataField.new('650', ' ', ' ', ['a', 'Psychoanalysis and literature'], ['x', 'History'], ['0', '01234'], ['3', 'Some part'])
      str = Marc21Semantics.assemble_lcsh(field)

      assert_equal "Psychoanalysis and literature — History", str
    end

    it "doesn't put subdivision in wrong place" do
      field = MARC::DataField.new('600', ' ', ' ', ['a', 'Eliot, George,'],['d', '1819-1880.'], ['t', 'Middlemarch'])
      str = Marc21Semantics.assemble_lcsh(field)

      assert_equal "Eliot, George, 1819-1880. Middlemarch", str
    end

    it "mixes non-subdivisions with subdivisions" do
      field = MARC::DataField.new('600', ' ', ' ', ['a', 'Eliot, George,'],['d', '1819-1880.'], ['t', 'Middlemarch'], ['x', 'Criticism.'])
      str = Marc21Semantics.assemble_lcsh(field)

      assert_equal "Eliot, George, 1819-1880. Middlemarch — Criticism", str
    end

    it "returns nil for a field with no relevant subfields" do
      field = MARC::DataField.new('650', ' ', ' ')
      assert_nil Marc21Semantics.assemble_lcsh(field)
    end

    describe "marc_lcsh_formatted macro" do
      it "smoke test" do
        @record = MARC::Reader.new(support_file_path  "george_eliot.marc").to_a.first
        @indexer.configure { to_field "lcsh", marc_lcsh_formatted }
        output = @indexer.map_record(@record)

        assert output["lcsh"].length > 0, "outputs data"
        assert output["lcsh"].include?("Eliot, George, 1819-1880 — Characters"), "includes a string its supposed to"

        assert_equal({}, @indexer.map_record(empty_record))

      end
    end
  end

  describe "extract_marc_filing_version" do
    before do
      @record = MARC::Reader.new(support_file_path  "the_business_ren.marc").to_a.first
    end

    it "works as expected" do
      @indexer.configure do
        to_field 'title_phrase', extract_marc_filing_version('245ab')
      end
      output = @indexer.map_record(@record)
      assert_equal ['Business renaissance quarterly'], output['title_phrase']
      assert_equal({}, @indexer.map_record(empty_record))

    end

    it "works with :include_original" do
      @indexer.configure do
        to_field 'title_phrase', extract_marc_filing_version('245ab', :include_original=>true)
      end
      output = @indexer.map_record(@record)
      assert_equal ['The Business renaissance quarterly', 'Business renaissance quarterly'], output['title_phrase']
      assert_equal({}, @indexer.map_record(empty_record))
    end

    it "doesn't do anything if you don't include the first subfield" do
      @indexer.configure do
        to_field 'title_phrase', extract_marc_filing_version('245h')
      end
      output = @indexer.map_record(@record)
      assert_equal ['[electronic resource].'], output['title_phrase']
      assert_equal({}, @indexer.map_record(empty_record))

    end


    it "dies if you pass it something else" do
      assert_raises(RuntimeError) do
        @indexer.configure do
          to_field 'title_phrase', extract_marc_filing_version('245ab', :include_original=>true, :uniq => true)
        end
      end
    end

  end



end
