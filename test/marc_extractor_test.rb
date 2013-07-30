# encoding: UTF-8

require 'test_helper'
require 'traject/marc_extractor'

require 'marc'

describe "Traject::MarcExtractor" do
  describe "#parse_marc_spec" do
    it "parses single spec with all elements" do
      parsed = Traject::MarcExtractor.parse_string_spec("245|1*|abcg")

      assert_kind_of Hash, parsed
      assert_equal 1, parsed.keys.length
      assert_kind_of Hash, parsed["245"]

      assert_kind_of Array, parsed["245"][:indicators]
      assert_equal 2, parsed["245"][:indicators].length
      assert_equal "1", parsed["245"][:indicators][0]
      assert_nil parsed["245"][:indicators][1]

      assert_kind_of Array, parsed["245"][:subfields]

    end

    it "parses a mixed bag" do
      parsed = Traject::MarcExtractor.parse_string_spec("245abcde:810:700|*4|bcd")

      assert_length 3, parsed

      #245abcde
      assert parsed["245"]
      assert_nil parsed["245"][:indicators]
      assert_equal %w{a b c d e}, parsed["245"][:subfields]

      #810
      assert parsed["810"]
      assert_nil parsed["810"][:indicators]
      assert_nil parsed["810"][:subfields]

      #700-*4bcd
      assert parsed["700"]
      assert_equal [nil, "4"], parsed["700"][:indicators]
      assert_equal %w{b c d}, parsed["700"][:subfields]
    end

    it "parses fixed field byte offsets" do
      parsed = Traject::MarcExtractor.parse_string_spec("005[5]:008[7-10]")

      assert_equal 5, parsed["005"][:bytes]
      assert_equal 7..10, parsed["008"][:bytes]
    end
  end

  describe "#extract_by_spec" do
    before do
      @record = MARC::Reader.new(support_file_path  "manufacturing_consent.marc").to_a.first
    end

    describe "extracts a basic case" do
      before do
        parsed_spec = Traject::MarcExtractor.parse_string_spec("700abcdef:856|*2|:505|1*|:245ba")
        @values = Traject::MarcExtractor.extract_by_spec(@record, parsed_spec)
      end

      it "returns an array" do
        assert_kind_of Array, @values
      end

      it "handles no subfields given" do
        a856s = @record.find_all {|f| f.tag == "856"}
        assert a856s, "Record must have 856 fields for this test to work"

        a856s.each do |field|
          assert @values.include?( field.subfields.collect(&:value).join(" "))
        end
      end

      it "does not have 505, due to non-matching indicators" do
        assert ! @values.find {|s| s.include? "propaganda model"}
      end



      it "respects original record order, for both fields and subfields" do
        expected = ["Manufacturing consent : the political economy of the mass media /",
                    "Chomsky, Noam.",
                    "Contributor biographical information http://www.loc.gov/catdir/bios/random051/2001050014.html",
                    "Publisher description http://www.loc.gov/catdir/description/random044/2001050014.html"]
        assert_equal expected, @values
      end
    end

    describe "extracts fixed fields" do
      it ", complete" do
        parsed_spec = Traject::MarcExtractor.parse_string_spec("001")
        values = Traject::MarcExtractor.extract_by_spec(@record, parsed_spec)

        assert_equal ["2710183"], values
      end
      it ", single byte offset" do
        parsed_spec = Traject::MarcExtractor.parse_string_spec("008[5]")
        values = Traject::MarcExtractor.extract_by_spec(@record, parsed_spec)

        assert_equal ["1"], values
      end
      it ", byte range" do
        parsed_spec = Traject::MarcExtractor.parse_string_spec("008[7-10]")
        values = Traject::MarcExtractor.extract_by_spec(@record, parsed_spec)

        assert_equal ["2002"], values
      end
    end

    describe "seperator argument" do
      it "causes non-join when nil" do
        parsed_spec = Traject::MarcExtractor.parse_string_spec("245")
        values = Traject::MarcExtractor.extract_by_spec(@record, parsed_spec, :seperator => nil)

        assert_length 3, values
      end

      it "can be non-default" do
        parsed_spec = Traject::MarcExtractor.parse_string_spec("245")
        values = Traject::MarcExtractor.extract_by_spec(@record, parsed_spec, :seperator => "!! ")

        assert_length 1, values
        assert_equal "Manufacturing consent :!! the political economy of the mass media /!! Edward S. Herman and Noam Chomsky ; with a new introduction by the authors.", values.first
      end
    end

    describe "extracts alternate script" do
      before do
        @record = MARC::Reader.new(support_file_path  "hebrew880s.marc").to_a.first
        @parsed_spec = Traject::MarcExtractor.parse_string_spec("245b")
      end
      it "from default :include" do

        values = Traject::MarcExtractor.extract_by_spec(@record, @parsed_spec)

        assert_length 2, values # both the original and the 880
        assert_equal ["ben Marṭin Buber le-Aharon Daṿid Gordon /", "בין מרטין בובר לאהרן דוד גורדון /"], values
      end
      it "with :only" do
        values = Traject::MarcExtractor.extract_by_spec(@record, @parsed_spec, :alternate_script => :only)

        assert_length 1, values
        assert_equal ["בין מרטין בובר לאהרן דוד גורדון /"], values
      end
      it "with false" do
        values = Traject::MarcExtractor.extract_by_spec(@record, @parsed_spec, :alternate_script => false)

        assert_length 1, values
        assert_equal ["ben Marṭin Buber le-Aharon Daṿid Gordon /"], values
      end
    end

    it "works with string second arg too" do
      values = Traject::MarcExtractor.extract_by_spec(@record, "245abc")

      assert_length 1, values
      assert values.first.include?("Manufacturing consent"), "Extracted value includes title"
    end

    it "returns empty array if no matching tags" do
      values = Traject::MarcExtractor.extract_by_spec(@record, "999abc")
      assert_equal [], values

      values = Traject::MarcExtractor.extract_by_spec(@record, "999")
      assert_equal [], values
    end

    it "returns empty array if matching tag but no subfield" do 
      values = Traject::MarcExtractor.extract_by_spec(@record, "245xyz")
      assert_equal [], values
    end

  end

  describe "#each_matching_line" do
    before do
      @record = MARC::Reader.new(support_file_path  "manufacturing_consent.marc").to_a.first
      @extractor = Traject::MarcExtractor.new(@record, "245abc")
    end
    it "yields two args" do
      called = false
      @extractor.each_matching_line do |field, spec|
        called = true
        assert_kind_of MARC::DataField, field
        assert_kind_of Hash, spec
      end
      assert called, "calls block"
    end
    it "yields three args" do
      called = false
      @extractor.each_matching_line do |field, spec, extractor|
        called = true
        assert_kind_of MARC::DataField, field
        assert_kind_of Hash, spec
        assert_kind_of Traject::MarcExtractor, extractor
        assert_same @extractor, extractor
      end
      assert called, "calls block"
    end
  end

  describe "#collect_matching_lines" do
    before do
      @record = MARC::Reader.new(support_file_path  "manufacturing_consent.marc").to_a.first
      @extractor = Traject::MarcExtractor.new(@record, "245abc")
    end
    it "collects with custom block" do
      results = @extractor.collect_matching_lines do |field, spec, extractor|
        extractor.collect_subfields(field, spec)
      end
      assert_equal ["Manufacturing consent : the political economy of the mass media / Edward S. Herman and Noam Chomsky ; with a new introduction by the authors."], results
    end
  end



end