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
      found = @cache.lookup("ruby_map")

      assert_kind_of Hash, found
      assert_equal "value1", found["key1"]
    end

    it "looks up yaml definitions" do
      found = @cache.lookup("yaml_map")

      assert_kind_of Hash, found
      assert_equal "value1", found["key1"]
    end

    it "freezes the hash" do
      found = @cache.lookup("yaml_map")

      assert found.frozen?
    end

    it "respects in-file default, even on second load" do
      map = Traject::TranslationMap.new("default_literal")
      map = Traject::TranslationMap.new("default_literal")

      assert_equal "DEFAULT LITERAL", map["not in the map"]
    end

    it "does not trigger default on explicit nil result" do
      map = Traject::TranslationMap.new({"alpha" => "one", "beta" => nil}, :default => "DEFAULT")

      assert_equal "one", map["alpha"]
      assert_nil map["beta"]
      assert_equal "DEFAULT", map["not_found_in_map"]
    end

    it "finds .rb over .yaml" do
      found = @cache.lookup("both_map")

      assert_equal "ruby", found["ruby"]
      assert_nil found["yaml"]
    end

    it "raises on syntax error in yaml" do
      exception = assert_raises(Psych::SyntaxError) do
        _found = @cache.lookup("bad_yaml")
      end

      assert  exception.message.include?("bad_yaml.yaml"), "exception message includes source file"
    end

    it "raises on syntax error in ruby" do
      exception = assert_raises(SyntaxError) do
        _found = @cache.lookup("bad_ruby")
      end
      assert  exception.message.include?("bad_ruby.rb"), "exception message includes source file"
    end

  end

  it "raises for not found" do
    assert_raises(Traject::TranslationMap::NotFound) { Traject::TranslationMap.new("this_does_not_exist") }
  end

  it "finds ruby defn" do
    map = Traject::TranslationMap.new("ruby_map")

    assert_equal "value1", map["key1"]
  end

  it "finds yaml defn" do
    map = Traject::TranslationMap.new("yaml_map")

    assert_equal "value1", map["key1"]
  end

  it "finds .properties defn" do
    map =Traject::TranslationMap.new("properties_map")

    assert_equal "Value1", map["key1"]
    assert_equal "Value2", map["key2"]
    assert_equal "Multi word value", map["key3"]
  end

  it "can use a hash instance too" do
    map = Traject::TranslationMap.new(
      "input_value" => "output_value"
    )

    assert_equal "output_value", map["input_value"]
  end

  it "can be initialized with another map" do
    map = Traject::TranslationMap.new({"alpha" => "one", "beta" => nil}, :default => "DEFAULT")

    new_map = Traject::TranslationMap.new(map)

    assert_equal map.to_hash, new_map.to_hash
    assert_equal map.default, new_map.default
  end

  it "respects __default__ literal" do
    map = Traject::TranslationMap.new("default_literal")

    assert_equal "DEFAULT LITERAL", map["not in the map"]
  end

  it "respects __default__ __passthrough__" do
    map = Traject::TranslationMap.new("default_passthrough")

    assert_equal "pass this through", map["pass this through"]
  end

  it "translate_array!" do
    map = Traject::TranslationMap.new("translate_array_test")
    arr = ["hello", "multiple", "goodbye", "nothing", "hello", "not present"]

    map.translate_array!(arr)

    assert_equal ["hola", "first", "second", "last thing", "buenas noches", "hola", "everything else"], arr
  end

  it "translate_array does not include nil values" do
    # TranslationMap can explicitly map to nil, meaning,
    # well, map to nothing. Make sure translate_array respects that.
    map = Traject::TranslationMap.new("alpha" => "one", "beta" => nil)

    values = map.translate_array(["alpha", "beta"])

    assert_equal ["one"], values
  end

  describe "#to_hash" do
    it "produces a hash" do
      map = Traject::TranslationMap.new("yaml_map")

      hash = map.to_hash

      assert_kind_of Hash, hash

      assert ! hash.frozen?, "#to_hash result is not frozen"

      refute_same hash, map.to_hash, "each #to_hash result is a copy"
    end

    it "does not include __default__ key" do
      map = Traject::TranslationMap.new("default_passthrough")

      refute map.to_hash.has_key?("__default__")
      assert_nil map.to_hash["__default__"]
    end

  end

  describe "#merge" do
    it "merges" do
      original = Traject::TranslationMap.new("yaml_map")
      override = Traject::TranslationMap.new("other" => "OVERRIDE", "new" => "NEW")

      merged = original.merge(override)

      assert_equal "value1",    merged["key1"]
      assert_equal "OVERRIDE",  merged["other"]
      assert_equal "NEW",       merged["new"]
    end

    it "passes through default from first map when no default in second" do
      original = Traject::TranslationMap.new("yaml_map", :default => "DEFAULT_VALUE")
      override = Traject::TranslationMap.new("other" => "OVERRIDE")

      merged = original.merge(override)

      assert_equal "DEFAULT_VALUE", merged.default
      assert_equal "DEFAULT_VALUE", merged["SOME_KEY_NOT_MATCHED"]
    end

    it "passes through default from second map when no default in first" do
      original = Traject::TranslationMap.new("yaml_map")
      override = Traject::TranslationMap.new({"other" => "OVERRIDE"}, :default => "DEFAULT_VALUE")

      merged = original.merge(override)

      assert_equal "DEFAULT_VALUE", merged.default
      assert_equal "DEFAULT_VALUE", merged["SOME_KEY_NOT_MATCHED"]
    end

    it "merges second default on top of first" do
      original = Traject::TranslationMap.new("yaml_map", :default => "DEFAULT_VALUE")
      override = Traject::TranslationMap.new({"other" => "OVERRIDE"}, :default => "NEW_DEFAULT_VALUE")

      merged = original.merge(override)

      assert_equal "NEW_DEFAULT_VALUE", merged.default
      assert_equal "NEW_DEFAULT_VALUE", merged["SOME_KEY_NOT_MATCHED"]
    end

    it "merges in a plain hash too" do
      original = Traject::TranslationMap.new("yaml_map")
      merged   = original.merge(
        "other" => "OVERRIDE",
        "new"   => "NEW"
      )

      assert_equal "value1",    merged["key1"]
      assert_equal "OVERRIDE",  merged["other"]
      assert_equal "NEW",       merged["new"]
    end

  end

end
