require 'test_helper'

describe "Traject::Indexer#settings" do
  before do
    @indexer = Traject::Indexer.new
  end

  it "starts out a Hash, that uses it's defaults" do
    assert_kind_of Hash, @indexer.settings

    Traject::Indexer.default_settings.each_pair do |key, value|
      assert_equal value, @indexer.settings[key]
    end
  end

  it "can fill_in_defaults!" do
    @indexer.settings.fill_in_defaults!

    assert_equal Traject::Indexer.default_settings, @indexer.settings
  end

  it "doesn't overwrite with fill_in_defaults!" do
    key = Traject::Indexer.default_settings.keys.first
    @indexer.settings[ key  ] = "MINE KEEP IT"

    assert_equal "MINE KEEP IT", @indexer.settings[key]

    @indexer.settings.fill_in_defaults!

    assert_equal "MINE KEEP IT", @indexer.settings[key]
  end

  it "can take argument to set" do
    @indexer.settings("foo" => "foo", "bar" => "bar")

    assert_equal "foo", @indexer.settings["foo"]
    assert_equal "bar", @indexer.settings["bar"]
  end

  it "has settings DSL to set" do
    @indexer.configure do
      settings do
        store "foo", "foo"
      end
    end

    assert_equal "foo", @indexer.settings["foo"]
  end

  it "merges new values, not completely replaces" do
    @indexer.settings("one" => "original", "two" => "original", "three" => "original", "four" => "original")

    @indexer.settings do
      store "two", "second"
      store "three", "second"
    end

    @indexer.settings do
      store "three", "third"
    end

    @indexer.settings("four" => "fourth")

    {"one" => "original", "two" => "second", "three" => "third", "four" => "fourth"}.each_pair do |key, value|
      assert_equal value, @indexer.settings[key]
    end
  end

  it "is indifferent between string and symbol" do
    @indexer.settings[:foo] = "foo 1"
    @indexer.settings["foo"] = "foo 2"

    assert_equal "foo 2", @indexer.settings[:foo]

    @indexer.settings do
      store "foo", "foo 3"
      store :foo, "foo 4"
    end

    assert_equal "foo 4", @indexer.settings["foo"]
  end

  it "implements #provide as cautious setter" do
    @indexer.settings[:a] = "original"

    @indexer.settings do
      provide :a, "new"
      provide :b, "new"
    end

    assert_equal "original", @indexer.settings[:a]
    assert_equal "new", @indexer.settings[:b]
  end

  it "has reverse_merge" do
    settings = Traject::Indexer::Settings.new("a" => "original", "b" => "original")

    new_settings = settings.reverse_merge(:a => "new",  :c => "new")

    assert_kind_of Traject::Indexer::Settings, new_settings

    assert_equal "original", new_settings["a"]
    assert_equal "original", new_settings["b"]
    assert_equal "new", new_settings["c"]
  end

  it "has reverse_merge!" do
    settings = Traject::Indexer::Settings.new("a" => "original", "b" => "original")

    settings.reverse_merge!(:a => "new",  :c => "new")

    assert_kind_of Traject::Indexer::Settings, settings

    assert_equal "original", settings["a"]
    assert_equal "original", settings["b"]
    assert_equal "new", settings["c"]
  end

  describe "inspect" do
    it "keeps keys ending in 'password' out of inspect" do
      settings = Traject::Indexer::Settings.new("a" => "a",
        "password" => "password", "some_password" => "password",
        "some.password" => "password")

      parsed = eval( settings.inspect )
      assert_equal( {"a" => "a", "password" => "[hidden]", "some_password" => "[hidden]", "some.password" => "[hidden]"}, parsed)
    end
  end

  describe "order of precedence" do
    it "args beat 'provides'" do
      # args come from command-line in typical use

      @indexer = Traject::Indexer.new(sample: "from args")
      @indexer.settings do
        provide :sample, "from config"
      end
      @indexer.settings.fill_in_defaults!

      assert_equal "from args", @indexer.settings["sample"]
    end

    it "args beat defaults" do
      key = Traject::Indexer.default_settings.keys.first
      @indexer = Traject::Indexer.new(key.to_sym => "from args")
      @indexer.settings.fill_in_defaults!

      assert_equal "from args", @indexer.settings[key]
    end

    it "provide beats defaults" do
      key = Traject::Indexer.default_settings.keys.first
      @indexer.settings do
        provide key, "from config"
      end
      @indexer.settings.fill_in_defaults!

      assert_equal "from config", @indexer.settings[key]
    end
  end

end
