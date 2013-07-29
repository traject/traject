require 'test_helper'

describe "Traject::Indexer#each_record" do
  before do
    @indexer = Traject::Indexer.new
  end

  describe "checks arguments" do
    it "rejects no-arg block" do
      assert_raises(ArgumentError) do
        @indexer.each_record do
        end
      end
    end
    it "rejects three-arg block" do
      assert_raises(ArgumentError) do
        @indexer.each_record do |one, two, three|
        end
      end
    end
    it "accepts one-arg block" do
      @indexer.each_record do |record|
      end
    end
    it "accepts two-arg block" do
      @indexer.each_record do |record, context|
      end
    end
    it "accepts variable arity block" do
      @indexer.each_record do |*variable|
      end
    end
  end
end