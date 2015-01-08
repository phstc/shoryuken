require 'spec_helper'

describe 'Shoryuken::Worker' do
  let(:sqs_queue) { double 'SQS Queue' }
  let(:queue)     { 'default' }

  before do
    allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
  end

  describe '.perform_in' do
    it 'delays a message' do
      expect(sqs_queue).to receive(:send_message).with('message', {
        message_attributes: {
          'shoryuken_class' => {
            string_value: TestWorker.to_s,
            data_type: 'String'
          }
        },
        delay_seconds: 60
      })

      TestWorker.perform_in(60, 'message')
    end

    it 'raises an exception' do
      expect {
        TestWorker.perform_in(901, 'message')
      }.to raise_error 'The maximum allowed delay is 15 minutes'
    end
  end

  describe '.perform_at' do
    it 'delays a message' do
      expect(sqs_queue).to receive(:send_message).with('message', {
        message_attributes: {
          'shoryuken_class' => {
            string_value: TestWorker.to_s,
            data_type: 'String'
          }
        },
        delay_seconds: 60
      })

      TestWorker.perform_in(Time.now + 60, 'message')
    end

    it 'raises an exception' do
      expect {
        TestWorker.perform_in(Time.now + 901, 'message')
      }.to raise_error 'The maximum allowed delay is 15 minutes'
    end
  end

  describe '.perform_async' do
    it 'enqueues a message' do
      expect(sqs_queue).to receive(:send_message).with('message', {
        message_attributes: {
          'shoryuken_class' => {
            string_value: TestWorker.to_s,
            data_type: 'String'
          }
        }
      })

      TestWorker.perform_async('message')
    end

    it 'enqueues a message with options' do
      expect(sqs_queue).to receive(:send_message).with('delayed message', {
        delay_seconds: 60,
        message_attributes: {
          'shoryuken_class' => {
            string_value: TestWorker.to_s,
            data_type: 'String'
          }
        }
      })

      TestWorker.perform_async('delayed message', delay_seconds: 60)
    end
  end

  describe '.shoryuken_options' do
    it 'registers a worker' do
      expect(Shoryuken.workers['default']).to eq TestWorker
    end

    it 'accepts a block as queue name' do
      $queue_prefix = 'production'

      class NewTestWorker
        include Shoryuken::Worker

        shoryuken_options queue: ->{ "#{$queue_prefix}_default" }
      end

      expect(Shoryuken.workers['production_default']).to eq NewTestWorker
      expect(NewTestWorker.get_shoryuken_options['queue']).to eq 'production_default'
    end
  end

  describe '.server_middleware' do
    before do
      class FakeMiddleware
        def call(*args)
          yield
        end
      end
    end

    context 'no middleware is defined in the worker' do
      it 'returns the list of global middlewares' do
        expect(TestWorker.server_middleware).to satisfy do |chain|
          chain.exists?(Shoryuken::Middleware::Server::Timing)
        end

        expect(TestWorker.server_middleware).to satisfy do |chain|
          chain.exists?(Shoryuken::Middleware::Server::AutoDelete)
        end
      end
    end

    context 'the worker clears the middleware chain' do
      before do
        class NewTestWorker2
          include Shoryuken::Worker

          server_middleware do |chain|
            chain.clear
          end
        end
      end

      it 'returns an empty list' do
        expect(NewTestWorker2.server_middleware.entries).to be_empty
      end

      it 'does not affect the global middleware chain' do
        expect(Shoryuken.server_middleware.entries).not_to be_empty
      end
    end

    context 'the worker modifies the chain' do
      before do
        class NewTestWorker3
          include Shoryuken::Worker

          server_middleware do |chain|
            chain.remove Shoryuken::Middleware::Server::Timing
            chain.insert_before Shoryuken::Middleware::Server::AutoDelete, FakeMiddleware
          end
        end
      end

      it 'returns the combined global and worker middlewares' do
        expect(NewTestWorker3.server_middleware).not_to satisfy do |chain|
          chain.exists?(Shoryuken::Middleware::Server::Timing)
        end

        expect(NewTestWorker3.server_middleware).to satisfy do |chain|
          chain.exists?(FakeMiddleware)
        end

        expect(NewTestWorker3.server_middleware).to satisfy do |chain|
          chain.exists?(Shoryuken::Middleware::Server::AutoDelete)
        end
      end

      it 'does not affect the global middleware chain' do
        expect(Shoryuken.server_middleware).to satisfy do |chain|
          chain.exists?(Shoryuken::Middleware::Server::Timing)
        end

        expect(Shoryuken.server_middleware).to satisfy do |chain|
          chain.exists?(Shoryuken::Middleware::Server::AutoDelete)
        end

        expect(Shoryuken.server_middleware).not_to satisfy do |chain|
          chain.exists?(FakeMiddleware)
        end
      end
    end
  end
end
