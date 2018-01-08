require 'test_helper'

describe "Traject::Indexer#process_with" do
  let(:input_records) { [
    { one: "one" },
    { two: "two" },
    { three: "three" }
  ] }
  let(:array_writer) { Traject::Indexer::ArrayWriter.new }
  let(:indexer) {
    Traject::Indexer.new do
      to_field "records", lambda { |rec, acc|
        acc << rec
      }
    end
  }

  it "processes" do
    writer = indexer.process_with(input_records, array_writer)
    assert_equal([{"records"=>[{:one=>"one"}]}, {"records"=>[{:two=>"two"}]}, {"records"=>[{:three=>"three"}]}], writer.values)
  end

  describe "calls close" do
    before do
      array_writer.extend(Module.new do
        def close
          @close_called = true
        end
        def close_called?
          @close_called
        end
      end)
    end

    it "calls by default" do
      writer = indexer.process_with(input_records, array_writer)
      assert writer.close_called?
    end

    it "does not call if told not to" do
      writer = indexer.process_with(input_records, array_writer, close_writer: false)
      assert ! writer.close_called?
    end
  end

  describe "after_processing steps" do
      let(:indexer) {
        Traject::Indexer.new do
          after_processing do
            raise "Don't call me"
          end
        end
      }
    it "are not called" do
      # should not raise
      indexer.process_with(input_records, array_writer)
    end
  end
end
