require 'test_helper'
require 'traject/translation_map'

describe "TranslationMap" do
  describe "::Cache" do
    before do
      @cache = Traject::TranslationMap::Cache.new
    end


    it "returns nil on not found" do
      assert_nil @cache.lookup("can_not_be_found")
    end

    it "looks up ruby definitions" do
      # ./test is on load path for testing, so...
      found = @cache.lookup("test_support/translation_maps/ruby_map")

      assert_kind_of Hash, found
      assert_equal "value1", found["key1"]
    end

    it "looks up yaml definitions" do
      found = @cache.lookup("test_support/translation_maps/yaml_map")

      assert_kind_of Hash, found
      assert_equal "value1", found["key1"]
    end

    it "finds .rb over .yaml" do
      found = @cache.lookup("test_support/translation_maps/both_map")

      assert_equal "ruby", found["ruby"]
      assert_nil found["yaml"]
    end

    it "raises on syntax error in yaml" do
      exception = assert_raises(Psych::SyntaxError) do
        found = @cache.lookup("test_support/translation_maps/bad_yaml")
      end

      assert  exception.message.include?("test/test_support/translation_maps/bad_yaml.yaml"), "exception message includes source file"
    end

    it "raises on syntax error in ruby" do
      exception = assert_raises(SyntaxError) do
        found = @cache.lookup("test_support/translation_maps/bad_ruby")
      end
      assert  exception.message.include?("test/test_support/translation_maps/bad_ruby.rb"), "exception message includes source file"
    end

  end

end