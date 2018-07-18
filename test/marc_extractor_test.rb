# encoding: UTF-8

require 'test_helper'
require 'traject/marc_extractor'

require 'marc'

describe "Traject::MarcExtractor" do
  it "is frozen read-only" do
    extractor = Traject::MarcExtractor.new("100abcde", :seperator => ";")
    assert extractor.frozen?
    assert extractor.spec_set.frozen?
    assert extractor.options.frozen?
  end


  describe "#parse_marc_spec" do
    it "parses single spec with all elements" do
      parsed = Traject::MarcExtractor::Spec.hash_from_string("245|1*|abcg")

      assert_kind_of Hash, parsed
      assert_equal 1, parsed.keys.length
      spec = parsed['245'].first
      assert_kind_of Traject::MarcExtractor::Spec, spec

      assert_equal "1", spec.indicator1
      assert_nil spec.indicator2

      assert_kind_of Array, spec.subfields
    end

    it "parses specset from an array" do
      parsed  = Traject::MarcExtractor::SpecSet.new(%w[245abcde 810 700|*4|bcd])
      assert_equal parsed.tags, %w[245 810 700]
    end

    it "parses a mixed bag" do
      parsed  = Traject::MarcExtractor::Spec.hash_from_string("245abcdes:810:700|*4|bcd")
      spec245 = parsed['245'].first
      spec810 = parsed['810'].first
      spec700 = parsed['700'].first

      assert_length 3, parsed

      #245abcde
      assert spec245
      assert_nil spec245.indicator1
      assert_nil spec245.indicator2
      assert_equal %w{a b c d e s}, spec245.subfields

      #810
      assert spec810
      assert_nil spec810.indicator1
      assert_nil spec810.indicator2
      assert_nil spec810.subfields, "No subfields"

      #700-*4bcd
      assert spec700
      assert_nil spec700.indicator1
      assert_equal "4", spec700.indicator2
      assert_equal %w{b c d}, spec700.subfields
    end

    it "parses from an array" do
      parsed  = Traject::MarcExtractor::Spec.hash_from_string(%w[245abcde 810 700|*4|bcd])
      _spec245 = parsed['245'].first
      _spec810 = parsed['810'].first
      _spec700 = parsed['700'].first

      assert_length 3, parsed
    end



    it "parses fixed field byte offsets" do
      parsed = Traject::MarcExtractor::Spec.hash_from_string("005[5]:008[7-10]")

      assert_equal 5, parsed["005"].first.bytes
      assert_equal 7..10, parsed["008"].first.bytes
    end

    it "allows arrays of specs" do
      parsed = Traject::MarcExtractor::Spec.hash_from_string %w(
        245abcde
        810
        700|*4|bcd
      )
      assert_length 3, parsed
    end

    it "allows mixture of array and colon-delimited specs" do
      parsed = Traject::MarcExtractor::Spec.hash_from_string %w(
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
  describe "#specs_covering_field" do
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
        assert_equal( [Traject::MarcExtractor::Spec.new(:tag => "245")], @extractor.specs_covering_field(@a880_245) )
        assert_equal [],   @extractor.specs_covering_field(@a880_100)
      end
      it "does not find spec for 880 if disabled" do
        @extractor = Traject::MarcExtractor.new("245", :alternate_script => false)
        assert_equal [], @extractor.specs_covering_field(@a880_245)
      end
      it "finds only 880 if so configured" do
        @extractor = Traject::MarcExtractor.new("245", :alternate_script => :only)
        assert_equal [], @extractor.specs_covering_field(@a245)
        assert_equal([Traject::MarcExtractor::Spec.new(:tag => "245")],  @extractor.specs_covering_field(@a880_245))
      end
    end
  end

  describe "#extract_by_spec" do
    before do
      @record = MARC::Reader.new(support_file_path "manufacturing_consent.marc").first
    end

    describe "extracts a basic case" do
      before do
        @parsed_spec = Traject::MarcExtractor::Spec.hash_from_string("700abcdef:856|*2|:505|1*|:245ba")
        @values      = Traject::MarcExtractor.new(@parsed_spec).extract(@record)
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
        assert !@values.find { |s| s.include? "propaganda model" }, @values
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
        parsed_spec = Traject::MarcExtractor::Spec.hash_from_string("001")
        values      = Traject::MarcExtractor.new(parsed_spec).extract(@record)

        assert_equal ["2710183"], values
      end
      it ", single byte offset" do
        parsed_spec = Traject::MarcExtractor::Spec.hash_from_string("008[5]")
        values      = Traject::MarcExtractor.new(parsed_spec).extract(@record)

        assert_equal ["1"], values
      end
      it ", byte range" do
        parsed_spec = Traject::MarcExtractor::Spec.hash_from_string("008[7-10]")
        values      = Traject::MarcExtractor.new(parsed_spec).extract(@record)

        assert_equal ["2002"], values
      end
    end

    describe "separator argument" do
      it "causes non-join when nil" do
        parsed_spec = Traject::MarcExtractor::Spec.hash_from_string("245")
        values      = Traject::MarcExtractor.new(parsed_spec, :separator => nil).extract(@record)

        assert_length 3, values
      end

      it "can be non-default" do
        parsed_spec = Traject::MarcExtractor::Spec.hash_from_string("245")
        values      = Traject::MarcExtractor.new(parsed_spec, :separator => "!! ").extract(@record)

        assert_length 1, values
        assert_equal "Manufacturing consent :!! the political economy of the mass media /!! Edward S. Herman and Noam Chomsky ; with a new introduction by the authors.", values.first
      end
    end

    describe "extracts alternate script" do
      before do
        @record      = MARC::Reader.new(support_file_path  "hebrew880s.marc").to_a.first
        @parsed_spec = Traject::MarcExtractor::Spec.hash_from_string("245b")
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
        assert_kind_of Traject::MarcExtractor::Spec, spec
      end
      assert called, "calls block"
    end
    it "yields three args" do
      called = false
      @extractor.each_matching_line(@record) do |field, spec, extractor|
        called = true
        assert_kind_of MARC::DataField, field
        assert_kind_of Traject::MarcExtractor::Spec, spec
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
      extractor = Traject::MarcExtractor.cached("245abc", :separator => nil)
      spec_set  = extractor.spec_set

      assert extractor.options[:separator].nil?, "extractor options[:separator] is nil"
      assert_equal([Traject::MarcExtractor::Spec.new(:tag => "245", :subfields => ["a", "b", "c"])], spec_set.specs_for_tag('245'))
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

    it "allows repeated tags with indicators specs" do
      extractor = Traject::MarcExtractor.new("245|1*|a:245|2*|b")
      @record.append(MARC::DataField.new('245', '2', '0', ['a', 'Subfield A Value'], ['b', 'Subfield B Value']))
      results = extractor.extract(@record)
      assert_equal ['Manufacturing consent :', 'Subfield B Value'], results
    end




    it "provides multiple values for repeated subfields with single specified subfield" do
      ex = Traject::MarcExtractor.new("245a")
      f = @record.fields('245').first
      title_a = f['a']
      f.append(MARC::Subfield.new('a', title_a))
      results = ex.extract(@record)
      assert_equal [title_a, title_a], results
    end

    it "concats single subfield spec when given as eg 245aa" do
      ex = Traject::MarcExtractor.new("245aa")
      f = @record.fields('245').first
      title_a = f['a']
      f.append(MARC::Subfield.new('a', title_a))
      results = ex.extract(@record)
      assert_equal ["#{title_a} #{title_a}"], results
    end

    it "provides single value for repeated subfields with multiple specified subfields" do
      ex = Traject::MarcExtractor.new("245ab")
      f = @record.fields('245').first
      title_a = f['a']
      title_b = f['b']
      f.append(MARC::Subfield.new('a', title_a))
      results = ex.extract(@record)
      assert_equal ["#{title_a} #{title_b} #{title_a}"], results

    end

    it "provides single value for repeated subfields with no specified subfield" do
      ex = Traject::MarcExtractor.new("245")
      f = @record.fields('245').first
      title_a = f['a']
      f.append(MARC::Subfield.new('a', title_a))
      results = ex.extract(@record)
      assert_equal 1, results.size
    end




    it "allows repeated tags for a control field" do
      extractor = Traject::MarcExtractor.new("001[0-1]:001[0-3]")
      values = extractor.extract(@record)
      assert_equal ["27", "2710"], values
    end

    it "associates indicators properly with repeated tags" do
      @record = MARC::Record.new
      @record.append MARC::DataField.new("100", '1', ' ', ['a', '100a first indicator 1'], ['b', 'should not include 100|1|b'])
      @record.append MARC::DataField.new("100", '2', ' ', ['b', '100b first indicator 2'], ['a', 'should not include 100|2|a'])

      extractor = Traject::MarcExtractor.new("100|1*|a:100|2*|b")

      values = extractor.extract(@record)

      assert_equal ['100a first indicator 1', '100b first indicator 2'], values
    end

  end

  describe "MarcExtractor::Spec" do
    describe "==" do
      it "equals when equal" do
        assert_equal Traject::MarcExtractor::Spec.new(:subfields => %w{a b c}), Traject::MarcExtractor::Spec.new(:subfields => %w{a b c})
      end
      it "does not equal when not" do
        refute_equal Traject::MarcExtractor::Spec.new(:subfields => %w{a b c}), Traject::MarcExtractor::Spec.new(:subfields => %w{a b c}, :indicator2 => '1')
      end
    end
  end


end
