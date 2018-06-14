require 'test_helper'

describe "Traject::Indexer.to_field" do
  before do
    @indexer = Traject::Indexer.new
  end
  describe "checks it's arguments" do
    it "rejects nil first arg" do
      assert_raises(Traject::Indexer::NamingError) { @indexer.to_field(nil) }
    end
    it "rejects empty string first arg" do
      assert_raises(Traject::Indexer::NamingError) {@indexer.to_field("")}
    end
    it "rejects non-string first arg" do
      assert_raises(Traject::Indexer::NamingError) {@indexer.to_field(:symbol)}
    end

    it "rejects one-arg lambda" do
      assert_raises(Traject::Indexer::ArityError) do
        @indexer.to_field("foo") do |one_arg|
        end
      end
    end
    it "rejects four-arg lambda" do
      assert_raises(Traject::Indexer::ArityError) do
        @indexer.to_field("foo") do |one_arg, two_arg, three_arg, four_arg|
        end
      end
    end
    it "accepts two arg lambda" do
      @indexer.to_field("foo") do |one, two|
      end
    end
    it "accepts three arg lambda" do
      @indexer.to_field("foo") {|one, two, three| one }
    end
    it "accepts variable lambda" do
      @indexer.to_field("foo") do |*variable|
      end
    end
  end

  it "outputs error with source location" do
    begin
      @indexer.to_field('foo') {|one, two| }
      @indexer.to_field('') {|one, two| }   # bad field name
      flunk("Should have rejected empty field name")
    rescue Traject::Indexer::NamingError => e
      assert_match(/at .*\/.*:\d+/, e.message)
    rescue
      flunk("Should only fail with a NamingError")
    end
  end

  # Just verifying this is how it works
  it "doesn't allow you to just wholesale assignment to the accumulator" do
    @indexer.to_field('foo') do |rec, acc|
      acc = ['hello']
    end
    output = @indexer.map_record('never looked at')
    assert_nil output['foo']
  end

  it "allows use of accumulator.replace" do
    @indexer.to_field('foo') do |rec, acc|
      acc.replace ['hello']
    end
    output = @indexer.map_record('never looked at')
    assert_equal ['hello'], output['foo']
  end

  describe "supports multiple procs" do
    it "with no block" do
      @indexer.to_field "foo",
        lambda {|record, acc| acc << "one"},
        lambda {|record, acc| acc << "two"},
        lambda {|record, acc| acc << "three"}

      output = @indexer.map_record('never looked at')
      assert_equal ['one', 'two', 'three'], output['foo']
    end

    it "with a block too" do
      @indexer.to_field "foo",
        lambda {|record, acc| acc << "one"},
        lambda {|record, acc| acc << "two"} do |record, acc|
          acc << "three"
      end

      output = @indexer.map_record('never looked at')
      assert_equal ['one', 'two', 'three'], output['foo']
    end
  end

  describe "with an array argument" do
    it "indexes to multiple fields" do
      @indexer.to_field ["field1", "field2", "field3"], lambda {|rec, acc| acc << "value" }
      output = @indexer.map_record('never looked at')
      assert_equal({ "field1" => ["value"], "field2" => ["value"], "field3" => ["value"] }, output)
    end
  end
end
