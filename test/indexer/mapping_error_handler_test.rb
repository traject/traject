require 'test_helper'

describe 'Custom mapping error handler' do
  # the exception thrown by the custom handler
  class CustomException < StandardError; end

  let(:indexer_default_handling) { Traject::Indexer.new }

  let(:indexer_custom_handler) do
    indexer = Traject::Indexer.new
    indexer.settings['mapping_error_handler'] = lambda do |ctx, step, e|
      raise CustomException, "custom handler called #{ctx}: #{step}, #{e}"
    end
    indexer
  end

  let(:indexer_custom_handler_with_logger) do
    indexer = Traject::Indexer.new
    indexer.settings['mapping_error_handler'] = lambda do |ctx, step, e|
      logger.info("you better believe I'm invoked")
      raise CustomException, "custom handler called #{ctx}: #{step}, #{e}"
    end
    indexer
  end


  it 'invokes the default handler when custom handler is not set' do
    output = StringIO.new
    logger =Logger.new(output)
    indexer_default_handling.logger = logger
    indexer_default_handling.instance_eval do 
      to_field 'id' do |_, _, _|
        raise ValueError, "I just like raising errors"
      end
    end
    begin
      indexer_custom_handler.map_record({})
      assert "Should have raised an exception", false
    rescue StandardError => e
      assert_equals "I just like raising errors", e.msg
      assert output.string =~ /Unexpected error on record/
    end
  end

  it 'invokes the custom handler when set' do
    indexer_custom_handler.instance_eval do
      to_field 'id' do |_ ,_ ,_ |
        raise 'this was always going to fail'
      end
    end
    assert_raises(CustomException) { indexer_custom_handler.map_record({}) }
  end

  it 'puts indexer\'s logger in the scope of the custom handler' do
    begin
      indexer_custom_handler_with_logger.instance_eval do
        to_field 'id' do |_, _, _|
          raise CustomException, "this should be thrown"
        end
      end
      indexer_custom_handler_with_logger.map_record({})
      assert false, "That should have thrown an exception"
    rescue CustomException =>e
      assert true
    end
  end



end
