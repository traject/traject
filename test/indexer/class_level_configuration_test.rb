require 'test_helper'

describe "Class-level configuration of Indexer sub-class" do
  class TestIndexerSubclass < Traject::Indexer
    configure do
      to_field "field", literal("value")
      each_record do |rec, context|
        context.output_hash["from_each_record"] ||= []
        context.output_hash["from_each_record"] << "value"
      end
    end
  end

  before do
    @indexer = TestIndexerSubclass.new
  end

  it "uses class-level configuration" do
    result = @indexer.map_record(Object.new)

    assert_equal ['value'], result['field']
    assert_equal ['value'], result['from_each_record']
  end

  it "uses class-level configuration and instance-level configuration" do
    @indexer.configure do
      to_field "field", literal("from-instance-config")
      to_field "instance_field", literal("from-instance-config")
    end

    result = @indexer.map_record(Object.new)
    assert_equal ['value', 'from-instance-config'], result['field']
    assert_equal ['from-instance-config'], result["instance_field"]
  end

  describe "with multi-level subclass" do
    class TestIndexerSubclassSubclass < TestIndexerSubclass
      configure do
        to_field "field", literal("from-sub-subclass")
        to_field "subclass_field", literal("from-sub-subclass")
      end
    end

    before do
      @indexer = TestIndexerSubclassSubclass.new
    end

    it "uses configuraton from all inheritance" do
      result = @indexer.map_record(Object.new)

      assert_equal ['value', 'from-sub-subclass'], result['field']
      assert_equal ['value'], result['from_each_record']
      assert_equal ['from-sub-subclass'], result['subclass_field']
    end

    it "uses configuraton from all inheritance plus instance" do
      @indexer.configure do
        to_field "field", literal("from-instance")
        to_field "instance_field", literal("from-instance")
      end

      result = @indexer.map_record(Object.new)

      assert_equal ['value', 'from-sub-subclass', 'from-instance'], result['field']
      assert_equal ['from-instance'], result['instance_field']
    end
  end

end
