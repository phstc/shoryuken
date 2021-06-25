require 'spec_helper'

RSpec.describe Shoryuken::Worker::InlineExecutor do
  before do
    # Reset values on memory to set up right condition for InlineExecutor
    TestWorker.instance_variable_set(:@_server_chain, nil)
    Shoryuken.shoryuken_options.instance_variable_set(:@_server_chain, nil)
    Shoryuken.worker_executor = described_class
  end

  after do
    # Reset values on memory to not affect other examples
    TestWorker.instance_variable_set(:@_server_chain, nil)
    Shoryuken.shoryuken_options.instance_variable_set(:@_server_chain, nil)
    Shoryuken.worker_executor = Shoryuken::Worker::DefaultExecutor
  end

  describe '.perform_async' do
    specify do
      expect_any_instance_of(TestWorker).to receive(:perform).with(anything, 'test')

      TestWorker.perform_async('test')
    end
  end

  describe '.perform_in' do
    specify do
      expect_any_instance_of(TestWorker).to receive(:perform).with(anything, 'test')

      TestWorker.perform_in(60, 'test')
    end
  end

  context 'batch' do
    before do
      TestWorker.get_shoryuken_options['batch'] = true
    end

    after do
      TestWorker.get_shoryuken_options['batch'] = false
    end

    describe '.perform_async' do
      specify do
        expect_any_instance_of(TestWorker).to receive(:perform).with(anything, ['test'])

        TestWorker.perform_async('test')
      end
    end

    describe '.perform_in' do
      specify do
        expect_any_instance_of(TestWorker).to receive(:perform).with(anything, ['test'])

        TestWorker.perform_in(60, 'test')
      end
    end
  end

  describe 'with custom middleware' do
    subject do
      -> { worker_klass.perform_async({}) }
    end

    shared_examples 'middleware#call method called' do
      specify { is_expected.to output("Custom middleware called\n").to_stdout }
    end

    context 'register middleware for each worker' do
      let(:worker_klass) do
        middleware = Class.new do
          def call(*_)
            puts 'Custom middleware called'
          end
        end

        Class.new(TestWorker) do
          server_middleware do |chain|
            chain.add middleware
          end
        end
      end

      include_examples 'middleware#call method called'
    end

    context 'register middleware globally' do
      before do
        middleware = Class.new do
          def call(*_)
            puts 'Custom middleware called'
          end
        end

        Shoryuken.configure_server do |config|
          config.server_middleware do |chain|
            chain.add middleware
          end
        end
      end

      let(:worker_klass) do
        Class.new(TestWorker) do
          def perform(*_); end
        end
      end

      include_examples 'middleware#call method called'
    end
  end
end
