require 'test_helper'
require 'traject/macros/marc21'


describe "Traject::Macros::Marc21" do
  Marc21 = Traject::Macros::Marc21 # so we can just call it 'Marc21' in code below

  describe "#parse_marc_spec" do
    it "parses single spec with all elements" do
      parsed = Marc21.parse_string_spec("245-1*abcg")

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
      parsed = Marc21.parse_string_spec("245abcde:810:700-*4bcd")

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
      parsed = Marc21.parse_string_spec("005[5]:008[7-10]")

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
        parsed_spec = Marc21.parse_string_spec("700abcdef:856-*2:505-1*:245ba")
        @values = Marc21.extract_by_spec(@record, parsed_spec)
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
        parsed_spec = Marc21.parse_string_spec("001")
        values = Marc21.extract_by_spec(@record, parsed_spec)

        assert_equal ["2710183"], values
      end
      it ", single byte offset" do
        parsed_spec = Marc21.parse_string_spec("008[5]")
        values = Marc21.extract_by_spec(@record, parsed_spec)

        assert_equal ["1"], values
      end
      it ", byte range" do
        parsed_spec = Marc21.parse_string_spec("008[7-10]")
        values = Marc21.extract_by_spec(@record, parsed_spec)

        assert_equal ["2002"], values
      end
    end

  end

end