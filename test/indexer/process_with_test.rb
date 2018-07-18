require 'test_helper'

describe "Traject::Indexer#process_with" do
  let(:input_records) { [
    { one: "one" },
    { two: "two" },
    { three: "three" }
  ] }
  let(:array_writer) { Traject::ArrayWriter.new }
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

  describe "with block as destination" do
    it "calls block for each record" do
      received = []
      indexer.process_with(input_records) do |context|
        received << context
      end

      assert_equal 3, received.length
      assert received.all? { |o| o.kind_of?(Traject::Indexer::Context)}
      assert_equal input_records.collect { |r| [r] }, received.collect { |c| c.output_hash["records"] }
    end
  end

  describe "exceptions" do
    let(:indexer) {
      Traject::Indexer.new do
        to_field "foo", lambda { |rec, acc|
          if rec.keys.include?(:one)
            raise ArgumentError, "intentional"
          end

          acc << rec
        }
      end
    }

    describe "by default" do
      it "raises" do
        assert_raises(ArgumentError) do
          indexer.process_with(input_records, array_writer)
        end
      end
    end

    describe "with rescue_with" do
      it "calls block and keeps processing" do
        rescued = []
        rescue_lambda = lambda do |context, exception|
          rescued << {
            context: context,
            exception: exception
          }
        end

        _writer = indexer.process_with(input_records, array_writer, rescue_with: rescue_lambda)

        # not including the one that raised
        assert_equal 2, array_writer.contexts.length
        # and raise was called

        assert_equal 1, rescued.length
        assert rescued.first[:context].is_a?(Traject::Indexer::Context)
        assert_equal ArgumentError, rescued.first[:exception].class
        assert_equal "intentional", rescued.first[:exception].message
      end

      it "can raise from rescue" do
        rescue_lambda = lambda do |context, exception|
          raise exception
        end

        assert_raises(ArgumentError) do
          indexer.process_with(input_records, array_writer, rescue: rescue_lambda)
        end
      end
    end

    describe "skipped records" do
      let(:indexer) {
        Traject::Indexer.new do
          to_field "foo", literal("value")
          each_record do |record, context|
            context.skip!
          end
        end
      }
      it "calls on_skipped, does not send to writer" do
        skip_calls = []
        on_skipped = lambda { |*args| skip_calls << args }

        writer = indexer.process_with(input_records, array_writer, on_skipped: on_skipped)

        assert_equal writer.values, [], "nothing sent to writer"
        assert_equal input_records.count, skip_calls.count, "skip proc called"
        assert skip_calls.all? {|a| a.length == 1 && a[0].kind_of?(Traject::Indexer::Context) }, "skip proc called with single arg"
      end
    end
  end
end
