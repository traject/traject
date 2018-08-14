require 'test_helper'
require 'rspec/mocks'

# MOST of ThreadPool is not tested directly at this point.
describe "Traject::ThreadPool" do
  include ::RSpec::Mocks::ExampleMethods

  # http://blog.plataformatec.com.br/2015/05/nobody-told-me-minitest-was-this-fun/
  def before_setup
    ::RSpec::Mocks.setup
    super
  end

  def after_teardown
    super
    ::RSpec::Mocks.verify
  ensure
    ::RSpec::Mocks.teardown
  end


  describe "disable_concurrency!" do

    it "disables concurrency" do
      allow(Traject::ThreadPool).to receive(:concurrency_disabled?).and_return(true)

      parent_thread_id = Thread.current.object_id

      work_thread_id = Concurrent::AtomicFixnum.new

      Traject::ThreadPool.new(10).maybe_in_thread_pool do
        work_thread_id.update { Thread.current.object_id  }
      end

      assert_equal parent_thread_id, work_thread_id.value
    end
  end
end
