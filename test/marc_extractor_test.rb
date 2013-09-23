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
      spec = parsed['245'].first
      assert_kind_of Hash, spec

      assert_kind_of Array, spec[:indicators]
      assert_equal 2, spec[:indicators].length
      assert_equal "1", spec[:indicators][0]
      assert_nil spec[:indicators][1]

      assert_kind_of Array, spec[:subfields]

    end

    it "parses a mixed bag" do
      parsed = Traject::MarcExtractor.parse_string_spec("245abcde:810:700|*4|bcd")
      spec245 = parsed['245'].first
      spec810 = parsed['810'].first
      spec700 = parsed['700'].first

      assert_length 3, parsed

      #245abcde
      assert spec245
      assert_nil spec245[:indicators]
      assert_equal %w{a b c d e}, spec245[:subfields]

      #810
      assert spec810
      assert_nil spec810[:indicators]
      assert_nil spec810[:subfields], "No subfields"

      #700-*4bcd
      assert spec700
      assert_equal [nil, "4"], spec700[:indicators]
      assert_equal %w{b c d}, spec700[:subfields]
    end

    it "parses fixed field byte offsets" do
      parsed = Traject::MarcExtractor.parse_string_spec("005[5]:008[7-10]")

      assert_equal 5, parsed["005"].first[:bytes]
      assert_equal 7..10, parsed["008"].first[:bytes]
    end
    
    it "allows arrays of specs" do
      parsed = Traject::MarcExtractor.parse_string_spec %w(
        245abcde
        810
        700|*4|bcd
      )
      assert_length 3, parsed
    end
    
    it "allows mixture of array and colon-delimited specs" do
      parsed = Traject::MarcExtractor.parse_string_spec %w(
        245abcde
        100:110:111
        810
        700|*4|bcd
      )
      assert_length 6, parsed
    end
      
    
  end

  # Mostly an internal method, not neccesarily API, but
  # an important one, so we unit test some parts of it.
  describe "#spec_covering_field" do
    describe "for alternate script tags" do
      before do
        @record = MARC::Reader.new(support_file_path  "hebrew880s.marc").to_a.first
        @extractor = Traject::MarcExtractor.new("245")

        @a245 = @record.fields.find {|f| f.tag == "245"}
        assert ! @a245.nil?, "Found a 245 to test"

        @a880_245 = @record.fields.find do |field|
          (field.tag == "880") && field['6'] &&
          "245" == field['6'].slice(0,3)
        end
        assert ! @a880_245.nil?, "Found an 880-245 to test"

        @a880_100 = @record.fields.find do |field|
          (field.tag == "880") && field['6'] &&
          "100" == field['6'].slice(0,3)
        end

        assert ! @a880_100.nil?, "Found an 880-100 to test"
      end
      it "finds spec for relevant 880" do
        assert_equal( [{}], @extractor.spec_covering_field(@a880_245) )
        assert_nil        @extractor.spec_covering_field(@a880_100)
      end
      it "does not find spec for 880 if disabled" do
        @extractor = Traject::MarcExtractor.new("245", :alternate_script => false)
        assert_nil @extractor.spec_covering_field(@a880_245) 
      end
      it "finds only 880 if so configured" do
        @extractor = Traject::MarcExtractor.new("245", :alternate_script => :only)
        assert_nil @extractor.spec_covering_field(@a245) 
        assert_equal([{}],  @extractor.spec_covering_field(@a880_245))
      end
    end
  end

  describe "#extract_by_spec" do
    before do
      @record = MARC::Reader.new(support_file_path  "manufacturing_consent.marc").to_a.first
    end

    describe "extracts a basic case" do
      before do
        parsed_spec = Traject::MarcExtractor.parse_string_spec("700abcdef:856|*2|:505|1*|:245ba")
        @values = Traject::MarcExtractor.new(parsed_spec).extract(@record)
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
        values = Traject::MarcExtractor.new(parsed_spec).extract(@record)

        assert_equal ["2710183"], values
      end
      it ", single byte offset" do
        parsed_spec = Traject::MarcExtractor.parse_string_spec("008[5]")
        values = Traject::MarcExtractor.new(parsed_spec).extract(@record)

        assert_equal ["1"], values
      end
      it ", byte range" do
        parsed_spec = Traject::MarcExtractor.parse_string_spec("008[7-10]")
        values = Traject::MarcExtractor.new(parsed_spec).extract(@record)

        assert_equal ["2002"], values
      end
    end

    describe "separator argument" do
      it "causes non-join when nil" do
        parsed_spec = Traject::MarcExtractor.parse_string_spec("245")
        values = Traject::MarcExtractor.new(parsed_spec, :separator => nil).extract(@record)

        assert_length 3, values
      end

      it "can be non-default" do
        parsed_spec = Traject::MarcExtractor.parse_string_spec("245")
        values = Traject::MarcExtractor.new(parsed_spec, :separator => "!! ").extract(@record)

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

        values = Traject::MarcExtractor.new(@parsed_spec).extract(@record)

        assert_length 2, values # both the original and the 880
        assert_equal ["ben Marṭin Buber le-Aharon Daṿid Gordon /", "בין מרטין בובר לאהרן דוד גורדון /"], values
      end
      it "with :only" do
        values = Traject::MarcExtractor.new(@parsed_spec, :alternate_script => :only).extract(@record)

        assert_length 1, values
        assert_equal ["בין מרטין בובר לאהרן דוד גורדון /"], values
      end
      it "with false" do
        values = Traject::MarcExtractor.new(@parsed_spec, :alternate_script => false).extract(@record)

        assert_length 1, values
        assert_equal ["ben Marṭin Buber le-Aharon Daṿid Gordon /"], values
      end
    end

    it "works with string second arg too" do
      values = Traject::MarcExtractor.new("245abc").extract(@record)

      assert_length 1, values
      assert values.first.include?("Manufacturing consent"), "Extracted value includes title"
    end

    it "returns empty array if no matching tags" do
      values = Traject::MarcExtractor.new("999abc").extract(@record)
      assert_equal [], values

      values = Traject::MarcExtractor.new("999").extract(@record)
      assert_equal [], values
    end

    it "returns empty array if matching tag but no subfield" do
      values = Traject::MarcExtractor.new("245xyz").extract(@record)
      assert_equal [], values
    end

  end

  describe "with bad data" do
    it "can ignore an 880 with no $6" do
      @record = MARC::Reader.new(support_file_path  "880_with_no_6.utf8.marc").to_a.first
      values = Traject::MarcExtractor.new("001").extract(@record)
      assert_equal ["3468569"], values
    end
  end

  describe "#each_matching_line" do
    before do
      @record = MARC::Reader.new(support_file_path  "manufacturing_consent.marc").to_a.first
      @extractor = Traject::MarcExtractor.new("245abc")
    end
    it "yields two args" do
      called = false
      @extractor.each_matching_line(@record) do |field, spec|
        called = true
        assert_kind_of MARC::DataField, field
        assert_kind_of Hash, spec
      end
      assert called, "calls block"
    end
    it "yields three args" do
      called = false
      @extractor.each_matching_line(@record) do |field, spec, extractor|
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
      @extractor = Traject::MarcExtractor.new("245abc")
    end
    it "collects with custom block" do
      results = @extractor.collect_matching_lines(@record) do |field, spec, extractor|
        extractor.collect_subfields(field, spec)
      end
      assert_equal ["Manufacturing consent : the political economy of the mass media / Edward S. Herman and Noam Chomsky ; with a new introduction by the authors."], results
    end
  end

  describe "MarcExtractor.cached" do
    it "creates" do
      ext = Traject::MarcExtractor.cached("245abc", :separator => nil)
      assert_equal({"245"=>[{:subfields=>["a", "b", "c"]}]}, ext.spec_hash)
      assert ext.options[:separator].nil?, "extractor options[:separator] is nil"
    end
    it "caches" do
      ext1 = Traject::MarcExtractor.cached("245abc", :separator => nil)
      ext2 = Traject::MarcExtractor.cached("245abc", :separator => nil)

      assert_same ext1, ext2
    end
  end


  describe "Allows multiple uses of the same tag" do
    before do
      @record = MARC::Reader.new(support_file_path  "manufacturing_consent.marc").to_a.first
    end
    
    it "allows repated tags for a variable field" do
      extractor = Traject::MarcExtractor.new("245a:245b")
      values = extractor.extract(@record)
      assert_equal ['Manufacturing consent :', 'the political economy of the mass media /'], values
    end
    
    it "works the same as ::separator=>nil" do
      ex1 = Traject::MarcExtractor.new("245a:245b")
      ex2 = Traject::MarcExtractor.new("245ab", :separator=>nil)
      assert_equal ex1.extract(@record), ex2.extract(@record)
    end
      
  
    it "allows repeated tags for a control field" do
      extractor = Traject::MarcExtractor.new("001[0-1]:001[0-3]")
      values = extractor.extract(@record)
      assert_equal ["27", "2710"], values
    end
  end
      

end