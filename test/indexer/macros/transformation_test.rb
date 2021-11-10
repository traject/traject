# Encoding: UTF-8

require 'test_helper'
require 'traject/indexer'

# should be built into every indexer
describe "Traject::Macros::Transformation" do
  before do
    @indexer = Traject::Indexer.new
    @record = nil
  end

  describe "translation_map" do
    it "translates" do
      @indexer.configure do
        to_field "cataloging_agency", literal("DLC"), translation_map("marc_040a_translate_test")
      end
      output = @indexer.map_record(@record)
      assert_equal ["Library of Congress"], output["cataloging_agency"]
    end

    it "can merge multiple" do
      @indexer.configure do
        to_field "result", literal("key_to_be_overridden"), translation_map("ruby_map", "yaml_map")
      end
      output = @indexer.map_record(@record)
      assert_equal ["value_from_yaml"], output["result"]
    end

    it "can merge multiple with hash" do
      @indexer.configure do
        to_field "result", literal("key_to_be_overridden"), translation_map("ruby_map", "yaml_map", {"key_to_be_overridden" => "value_from_inline_hash"})
      end
      output = @indexer.map_record(@record)
      assert_equal ["value_from_inline_hash"], output["result"]
    end
  end

  describe "transform" do
    it "transforms with block" do
      @indexer.configure do
        to_field "sample_field", literal("one"), literal("two"), transform(&:upcase)
      end
      output = @indexer.map_record(@record)
      assert_equal ["ONE", "TWO"], output["sample_field"]
    end

    it "transforms with proc arg" do
      @indexer.configure do
        to_field "sample_field", literal("one"), literal("two"), transform(->(val) { val.tr('aeiou', '!') })
      end
      output = @indexer.map_record(@record)
      assert_equal ["!n!", "tw!"], output["sample_field"]
    end

    it "transforms with both, in correct order" do
      @indexer.configure do
        to_field "sample_field", literal("one"), literal("two"), transform(->(val) { val.tr('aeiou', '!') }, &:upcase)
      end
      output = @indexer.map_record(@record)
      assert_equal ["!N!", "TW!"], output["sample_field"]
    end
  end

  describe "default" do
    it "adds default to empty accumulator" do
      @indexer.configure do
        to_field "test", default("default")
      end
      output = @indexer.map_record(@record)
      assert_equal ["default"], output["test"]
    end

    it "does not add default if value present" do
      @indexer.configure do
        to_field "test", literal("value"), default("defaut")
      end
      output = @indexer.map_record(@record)
      assert_equal ["value"], output["test"]
    end
  end

  describe "first_only" do
    it "takes only first in multi-value" do
      @indexer.configure do
        to_field "test", literal("one"), literal("two"), literal("three"), first_only
      end
      output = @indexer.map_record(@record)
      assert_equal ["one"], output["test"]
    end

    it "no-ops on nil" do
      @indexer.configure do
        to_field "test", first_only
      end
      output = @indexer.map_record(@record)
      assert_nil output["test"]
    end

    it "no-ops on single value" do
      @indexer.configure do
        to_field "test", literal("one"), first_only
      end
      output = @indexer.map_record(@record)
      assert_equal ["one"], output["test"]
    end
  end

  describe "unique" do
    it "uniqs" do
      @indexer.configure do
        to_field "test", literal("one"), literal("two"), literal("one"), literal("three"), unique
      end
      output = @indexer.map_record(@record)
      assert_equal ["one", "two", "three"], output["test"]
    end
  end

  describe "strip" do
    it "strips" do
      @indexer.configure do
        to_field "test", literal("  one"), literal(" two  "), strip
      end
      output = @indexer.map_record(@record)
      assert_equal ["one", "two"], output["test"]
    end

    it "strips unicode whitespace" do
      @indexer.configure do
        to_field "test", literal(" \u00A0 \u2002 one \u202F "), strip
      end
      output = @indexer.map_record(@record)
      assert_equal ["one"], output["test"]
    end
  end

  describe "split" do
    it "splits" do
      @indexer.configure do
        to_field "test", literal("one.two"), split(".")
      end
      output = @indexer.map_record(@record)
      assert_equal ["one", "two"], output["test"]
    end
  end

  describe "append" do
    it "appends suffix" do
      @indexer.configure do
        to_field "test", literal("one"), literal("two"), append(".suffix")
      end
      output = @indexer.map_record(@record)
      assert_equal ["one.suffix", "two.suffix"], output["test"]
    end
  end

  describe "prepend" do
    it "prepends prefix" do
      @indexer.configure do
        to_field "test", literal("one"), literal("two"), prepend("prefix.")
      end
      output = @indexer.map_record(@record)
      assert_equal ["prefix.one", "prefix.two"], output["test"]
    end
  end

  describe "gsub" do
    it "gsubs" do
      @indexer.configure do
        to_field "test", literal("one1212two23three"), gsub(/\d+/, ' ')
      end
      output = @indexer.map_record(@record)
      assert_equal ["one two three"], output["test"]
    end
  end

  describe "delete_if" do

    describe "argument is an Array" do
      it "filters out selected values from accumulatd values" do
        arg = [ "one", "three"]

        @indexer.configure do
          to_field "test", literal("one"), literal("two"), literal("three"), delete_if(arg)
        end

        output = @indexer.map_record(@record)
        assert_equal ["two"], output["test"]
      end
    end

    describe "argument is a Set" do
      it "filters out selected values from accumulatd values" do
        arg = [ "one", "three"].to_set

        @indexer.configure do
          to_field "test", literal("one"), literal("two"), literal("three"), delete_if(arg)
        end

        output = @indexer.map_record(@record)
        assert_equal ["two"], output["test"]
      end
    end

    describe "argument is a Regex" do
      it "filters out selected values from accumulatd values" do
        arg = /^t/

        @indexer.configure do
          to_field "test", literal("one"), literal("two"), literal("three"), delete_if(arg)
        end

        output = @indexer.map_record(@record)
        assert_equal ["one"], output["test"]
      end
    end

    describe "argument is a Procedure or Lambda" do
      it "filters out selected values from accumulatd values" do
        arg = ->(v) { v == "one" }

        @indexer.configure do
          to_field "test", literal("one"), literal("two"), literal("three"), delete_if(arg)
        end

        output = @indexer.map_record(@record)
        assert_equal ["two", "three"], output["test"]
      end
    end
  end

  describe "select" do

    describe "argument is an Array" do
      it "selects a subset of values from accumulatd values" do
        arg = [ "one", "three", "four"]

        @indexer.configure do
          to_field "test", literal("one"), literal("two"), literal("three"), select(arg)
        end

        output = @indexer.map_record(@record)
        assert_equal ["one", "three"], output["test"]
      end
    end

    describe "argument is a Set" do
      it "selects a subset of values from accumulatd values" do
        arg = [ "one", "three", "four"].to_set

        @indexer.configure do
          to_field "test", literal("one"), literal("two"), literal("three"), select(arg)
        end

        output = @indexer.map_record(@record)
        assert_equal ["one", "three"], output["test"]
      end
    end

    describe "argument is a Regex" do
      it "selects a subset of values from accumulatd values" do
        arg = /^t/

        @indexer.configure do
          to_field "test", literal("one"), literal("two"), literal("three"), select(arg)
        end

        output = @indexer.map_record(@record)
        assert_equal ["two", "three"], output["test"]
      end
    end

    describe "argument is a Procedure or Lambda" do
      it "selects a subset of values from accumulatd values" do
        arg = ->(v) { v != "one" }

        @indexer.configure do
          to_field "test", literal("one"), literal("two"), literal("three"), select(arg)
        end

        output = @indexer.map_record(@record)
        assert_equal ["two", "three"], output["test"]
      end
    end
  end

end
