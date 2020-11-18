require 'spec_helper'

RSpec.describe Shoryuken::Processor do
  let(:manager)   { double Shoryuken::Manager }
  let(:sqs_queue) { double Shoryuken::Queue, visibility_timeout: 30 }
  let(:queue)     { 'default' }

  let(:sqs_msg) do
    double(
      Shoryuken::Message,
      queue_url: queue,
      body: 'test',
      message_attributes: {},
      message_id: SecureRandom.uuid,
      receipt_handle: SecureRandom.uuid
    )
  end

  before do
    allow(manager).to receive(:async).and_return(manager)
    allow(manager).to receive(:real_thread)
    allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
  end

  subject { described_class.new(queue, sqs_msg) }

  describe '#process' do
    it 'sets log context' do
      expect(Shoryuken::Logging).to receive(:with_context).with("TestWorker/#{queue}/#{sqs_msg.message_id}")

      allow_any_instance_of(TestWorker).to receive(:perform)
      allow(sqs_msg).to receive(:body)

      subject.process
    end

    context 'when custom middleware' do
      let(:queue) { 'worker_called_middleware' }

      class WorkerCalledMiddleware
        def call(worker, queue, sqs_msg, _body)
          # called is defined with `allow(...).to receive(...)`
          worker.called(sqs_msg, queue)
          yield
        end
      end

      before do
        class WorkerCalledMiddlewareWorker
          include Shoryuken::Worker

          shoryuken_options queue: 'worker_called_middleware'

          def perform(sqs_msg, body); end
        end
      end

      context 'server' do
        before do
          allow_any_instance_of(Shoryuken::Options).to receive(:server?).and_return(true)
          WorkerCalledMiddlewareWorker.instance_variable_set(:@_server_chain, nil) # un-memoize middleware

          Shoryuken.configure_server do |config|
            config.server_middleware do |chain|
              chain.add WorkerCalledMiddleware
            end
          end
        end

        after do
          Shoryuken.configure_server do |config|
            config.server_middleware do |chain|
              chain.remove WorkerCalledMiddleware
            end
          end
        end

        it 'invokes middleware' do
          expect_any_instance_of(WorkerCalledMiddlewareWorker).to receive(:perform).with(sqs_msg, sqs_msg.body)
          expect_any_instance_of(WorkerCalledMiddlewareWorker).to receive(:called).with(sqs_msg, queue)

          subject.process
        end
      end

      context 'client' do
        before do
          allow_any_instance_of(Shoryuken::Options).to receive(:server?).and_return(false)
          WorkerCalledMiddlewareWorker.instance_variable_set(:@_server_chain, nil) # un-memoize middleware

          Shoryuken.configure_server do |config|
            config.server_middleware do |chain|
              chain.add WorkerCalledMiddleware
            end
          end
        end

        after do
          Shoryuken.configure_server do |config|
            config.server_middleware do |chain|
              chain.remove WorkerCalledMiddleware
            end
          end
        end

        it "doesn't invoke middleware" do
          expect_any_instance_of(WorkerCalledMiddlewareWorker).to receive(:perform).with(sqs_msg, sqs_msg.body)
          expect_any_instance_of(WorkerCalledMiddlewareWorker).to_not receive(:called).with(sqs_msg, queue)

          subject.process
        end
      end
    end

    it 'performs with delete' do
      TestWorker.get_shoryuken_options['auto_delete'] = true

      expect_any_instance_of(TestWorker).to receive(:perform).with(sqs_msg, sqs_msg.body)

      expect(sqs_queue).to receive(:delete_messages).with(entries: [{ id: '0', receipt_handle: sqs_msg.receipt_handle }])

      subject.process
    end

    it 'performs without delete' do
      TestWorker.get_shoryuken_options['auto_delete'] = false

      expect_any_instance_of(TestWorker).to receive(:perform).with(sqs_msg, sqs_msg.body)

      expect(sqs_queue).to_not receive(:delete_messages)

      subject.process
    end

    context 'when shoryuken_class header' do
      let(:sqs_msg) do
        double(
          Shoryuken::Message,
          queue_url: queue,
          body: 'test',
          message_attributes: {
            'shoryuken_class' => {
              string_value: TestWorker.to_s,
              data_type: 'String'
            }
          },
          message_id: SecureRandom.uuid,
          receipt_handle: SecureRandom.uuid
        )
      end

      it 'performs without delete' do
        Shoryuken.worker_registry.clear # unregister TestWorker

        expect_any_instance_of(TestWorker).to receive(:perform).with(sqs_msg, sqs_msg.body)

        expect(sqs_queue).to_not receive(:delete_messages)

        subject.process
      end
    end

    context 'when specifying a reloader' do
      before do
        Shoryuken.reloader = proc do |_|
          TestWorker.new.called
        end
      end

      after do
        Shoryuken.reloader = proc { |&block| block.call }
      end

      it 'wraps execution in reloader' do
        expect_any_instance_of(TestWorker).to receive(:called)
        expect_any_instance_of(TestWorker).to_not receive(:perform)

        subject.process
      end
    end
  end
end
