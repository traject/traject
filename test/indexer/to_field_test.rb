require 'test_helper'

describe "Traject::Indexer.to_field" do
  before do 
    @indexer = Traject::Indexer.new
  end
  describe "checks it's arguments" do
    it "rejects nil first arg" do
      assert_raises(ArgumentError) { @indexer.to_field(nil) }
    end
    it "rejects empty string first arg" do
      assert_raises(ArgumentError) {@indexer.to_field("")}
    end
    it "rejects one-arg lambda" do
      assert_raises(ArgumentError) do
        @indexer.to_field("foo") do |one_arg|

        end
      end
    end
    it "rejects four-arg lambda" do
      assert_raises(ArgumentError) do 
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
end