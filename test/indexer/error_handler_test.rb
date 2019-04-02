require 'test_helper'

describe 'Custom mapping error handler' do
  # the exception thrown by the custom handler
  class CustomFakeException < StandardError; end

  let(:indexer) { Traject::Indexer.new }

  it 'invokes the default handler when custom handler is not set' do
    output = StringIO.new
    logger =Logger.new(output)
    indexer.logger = logger
    indexer.configure do
      to_field 'id' do |_, _, _|
        raise CustomFakeException, "I just like raising errors"
      end
    end

    e = assert_raises(CustomFakeException) do
      indexer.map_record({})
    end

    assert_equal "I just like raising errors", e.message
    assert output.string =~ /while executing \(to_field \"id\" at .*error_handler_test.rb:\d+\)/
    assert output.string =~ /CustomFakeException: I just like raising errors/
  end

  it 'invokes the custom handler when set' do
    indexer.configure do
      settings do
        provide 'mapping_rescue', -> (ctx, e) {
          raise CustomFakeException, "custom handler called #{ctx.record_inspect}: #{ctx.index_step.inspect}, #{e.inspect}"
        }
      end

      to_field 'id' do |_context , _exception|
        raise 'this was always going to fail'
      end
    end
    e = assert_raises(CustomFakeException) { indexer.map_record({}) }
    assert e.message =~ /\(to_field \"id\" at .*error_handler_test.rb:\d+\)/
  end

  it "custom handler can skip and continue" do
    indexer.configure do
      settings do
        provide "mapping_rescue", -> (context, exception) {
          context.skip!
        }
      end

      to_field 'id' do |_context , _exception|
        raise 'this was always going to fail'
      end
    end

    assert_nil indexer.map_record({})
  end

  it "uses logger from settings" do
    desired_logger = Logger.new("/dev/null")
    set_logger = nil
    indexer.configure do
      settings do
        provide "logger", desired_logger
        provide "mapping_rescue", -> (ctx, e) {
          set_logger = ctx.logger
        }
      end
      to_field 'id' do |_context , _exception|
        raise 'this was always going to fail'
      end
    end
    indexer.map_record({})
    assert_equal desired_logger.object_id, set_logger.object_id
  end
end
