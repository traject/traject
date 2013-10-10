require 'test_helper'

describe "Traject::Indexer#each_record" do
  before do
    @indexer = Traject::Indexer.new
  end

  describe "checks arguments" do
    it "rejects no-arg block" do
      assert_raises(Traject::Indexer::ArityError) do
        @indexer.each_record do
        end
      end
    end
    it "rejects three-arg block" do
      assert_raises(Traject::Indexer::ArityError) do
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

    it "outputs error with source location" do
      begin
        @indexer.to_field('foo') {|one, two| }
        @indexer.each_record {|one, two, three| }   # bad arity
        flunk("Should have rejected bad arity ")
      rescue Traject::Indexer::ArityError => e
        assert_match(/each_record at .*\/.*:\d+/, e.message)
      rescue
        flunk("Should only fail with a ArityError")
      end
    end

    it "rejects each_record with a name (e.g., using a to_field syntax)" do
      assert_raises(Traject::Indexer::NamingError) do
        @indexer.each_record('bad_name') {|one, two| }
      end
    end

    it "reject each_record with no arguments/blocks at all" do
      assert_raises(ArgumentError) do
        @indexer.each_record()
      end
    end

  end
end
