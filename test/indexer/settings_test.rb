require 'test_helper'

describe "Traject::Indexer#settings" do 
  before do
    @indexer = Traject::Indexer.new
  end

  it "starts out empty hash" do
    assert_kind_of Hash, @indexer.settings
    assert_empty @indexer.settings
  end

  it "can take argument to set" do
    @indexer.settings("foo" => "foo", "bar" => "bar")

    assert_equal "foo", @indexer.settings["foo"]
    assert_equal "bar", @indexer.settings["bar"]
  end

  it "has settings DSL to set" do
    @indexer.instance_eval do
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

    expected_hash = {"one" => "original", "two" => "second", "three" => "third", "four" => "fourth"}
    assert_equal expected_hash, @indexer.settings
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



end