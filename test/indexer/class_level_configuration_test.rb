require 'test_helper'

describe "Class-level configuration of Indexer sub-class" do
  # Declaring a class inline in minitest isn't great, this really is a globally
  # available class now, other tests shouldn't re-use this class name. But it works
  # for testing for now.
  class TestIndexerSubclass < Traject::Indexer
    configure do
      settings do
        provide "class_level", "TestIndexerSubclass"
      end

      to_field "field", literal("value")
      each_record do |rec, context|
        context.output_hash["from_each_record"] ||= []
        context.output_hash["from_each_record"] << "value"
      end
    end

    def self.default_settings
      @default_settings ||= super.merge(
        "set_by_default_setting_no_override" => "TestIndexerSubclass",
        "set_by_default_setting" => "TestIndexerSubclass"
      )
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

  describe "multiple class-level configure" do
    class MultipleConfigureIndexer < Traject::Indexer
      configure do
        to_field "field", literal("value")
      end
      configure do
        to_field "field", literal("value from second configure")
        to_field "second_call", literal("value from second configure")
      end
    end

    before do
      @indexer = MultipleConfigureIndexer.new
    end

    it "lets you call class-level configure multiple times and aggregates" do
      result = @indexer.map_record(Object.new)
      assert_equal ['value', 'value from second configure'], result['field']
      assert_equal ['value from second configure'], result['second_call']
    end
  end

  describe "with multi-level subclass" do
    class TestIndexerSubclassSubclass < TestIndexerSubclass
      configure do
        settings do
          provide "class_level", "TestIndexerSubclassSubclass"
        end

        to_field "field", literal("from-sub-subclass")
        to_field "subclass_field", literal("from-sub-subclass")
      end

      def self.default_settings
        @default_settings ||= super.merge(
          "set_by_default_setting" => "TestIndexerSubclassSubclass"
        )
      end

    end

    before do
      @indexer = TestIndexerSubclassSubclass.new
    end

    it "lets subclass override settings 'provide'" do
      skip("This would be nice but is currently architecturally hard")
      assert_equal "TestIndexerSubclassSubclass", @indexer.settings["class_level"]
    end

    it "lets subclass override default settings" do
      assert_equal "TestIndexerSubclassSubclass", @indexer.settings["set_by_default_setting"]
      assert_equal "TestIndexerSubclass", @indexer.settings["set_by_default_setting_no_override"]
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
