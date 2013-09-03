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
  
  describe "gives location in error message" do

    it "finds no previous field on initial error" do
      begin
        @indexer.to_field('') {|one, two| }   # bad field name
        flunk("Should have rejected empty field name")
      rescue Traject::Indexer::NamingError => e
        assert_match(/no previous named fields/, e.message)
      rescue 
        flunk("Should only fail with a NamingError")
      end
    end

    it "finds first (only) field on error" do
      begin
        @indexer.to_field('foo') {|one, two| }
        @indexer.to_field('') {|one, two| }   # bad field name
        flunk("Should have rejected empty field name")
      rescue Traject::Indexer::NamingError => e
        assert_match(/foo/, e.message)
      rescue 
        flunk("Should only fail with a NamingError")
      end
    end
  end
  
end