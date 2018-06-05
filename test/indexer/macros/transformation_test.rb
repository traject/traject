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
      @indexer.instance_eval do
        to_field "cataloging_agency", literal("DLC"), translation_map("marc_040a_translate_test")
      end
      output = @indexer.map_record(@record)
      assert_equal ["Library of Congress"], output["cataloging_agency"]
    end
  end

  describe "default" do
    it "adds default to empty accumulator" do
      @indexer.instance_eval do
        to_field "test", default("default")
      end
      output = @indexer.map_record(@record)
      assert_equal ["default"], output["test"]
    end

    it "does not add default if value present" do
      @indexer.instance_eval do
        to_field "test", literal("value"), default("defaut")
      end
      output = @indexer.map_record(@record)
      assert_equal ["value"], output["test"]
    end
  end

  describe "first_only" do
    it "takes only first in multi-value" do
      @indexer.instance_eval do
        to_field "test", literal("one"), literal("two"), literal("three"), first_only
      end
      output = @indexer.map_record(@record)
      assert_equal ["one"], output["test"]
    end

    it "no-ops on nil" do
      @indexer.instance_eval do
        to_field "test", first_only
      end
      output = @indexer.map_record(@record)
      assert_nil output["test"]
    end

    it "no-ops on single value" do
      @indexer.instance_eval do
        to_field "test", literal("one"), first_only
      end
      output = @indexer.map_record(@record)
      assert_equal ["one"], output["test"]
    end
  end

  describe "unique" do
    it "uniqs" do
      @indexer.instance_eval do
        to_field "test", literal("one"), literal("two"), literal("one"), literal("three"), unique
      end
      output = @indexer.map_record(@record)
      assert_equal ["one", "two", "three"], output["test"]
    end
  end

  describe "strip" do
    it "strips" do
      @indexer.instance_eval do
        to_field "test", literal("  one"), literal(" two  "), strip
      end
      output = @indexer.map_record(@record)
      assert_equal ["one", "two"], output["test"]
    end

    it "strips unicode whitespace" do
      @indexer.instance_eval do
        to_field "test", literal(" \u00A0 \u2002 one \u202F "), strip
      end
      output = @indexer.map_record(@record)
      assert_equal ["one"], output["test"]
    end
  end

  describe "split" do
    it "splits" do
      @indexer.instance_eval do
        to_field "test", literal("one.two"), split(".")
      end
      output = @indexer.map_record(@record)
      assert_equal ["one", "two"], output["test"]
    end
  end

  describe "append" do
    it "appends suffix" do
      @indexer.instance_eval do
        to_field "test", literal("one"), literal("two"), append(".suffix")
      end
      output = @indexer.map_record(@record)
      assert_equal ["one.suffix", "two.suffix"], output["test"]
    end
  end

  describe "prepend" do
    it "prepends prefix" do
      @indexer.instance_eval do
        to_field "test", literal("one"), literal("two"), prepend("prefix.")
      end
      output = @indexer.map_record(@record)
      assert_equal ["prefix.one", "prefix.two"], output["test"]
    end
  end

  describe "gsub" do
    it "gsubs" do
      @indexer.instance_eval do
        to_field "test", literal("one1212two23three"), gsub(/\d+/, ' ')
      end
      output = @indexer.map_record(@record)
      assert_equal ["one two three"], output["test"]
    end
  end

end
