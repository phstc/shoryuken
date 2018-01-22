require 'spec_helper'
require 'active_job'
require 'shoryuken/extensions/active_job_adapter'

RSpec.describe ActiveJob::QueueAdapters::ShoryukenAdapter do
  let(:job) { double 'Job', id: '123', queue_name: 'queue' }
  let(:fifo) { false }
  let(:queue) { double 'Queue', fifo?: fifo }

  before do
    allow(Shoryuken::Client).to receive(:queues).with(job.queue_name).and_return(queue)
    allow(job).to receive(:serialize).and_return({
      'job_class'  => 'Worker',
      'job_id'     => job.id,
      'queue_name' => job.queue_name,
      'arguments'  => nil,
      'locale'     => nil
    })
  end

  describe '#enqueue' do
    specify do
      expect(queue).to receive(:send_message) do |hash|
        expect(hash[:message_deduplication_id]).to_not be
      end
      expect(Shoryuken).to receive(:register_worker).with(job.queue_name, described_class::JobWrapper)

      subject.enqueue(job)
    end

    context 'when fifo' do
      let(:fifo) { true }

      it 'does not include job_id in the deduplication_id' do
        expect(queue).to receive(:send_message) do |hash|
          message_deduplication_id = Digest::SHA256.hexdigest(JSON.dump(job.serialize.except('job_id')))

          expect(hash[:message_deduplication_id]).to eq(message_deduplication_id)
        end
        expect(Shoryuken).to receive(:register_worker).with(job.queue_name, described_class::JobWrapper)

        subject.enqueue(job)
      end
    end
  end

  describe '#enqueue_at' do
    specify do
      delay = 1

      expect(queue).to receive(:send_message) do |hash|
        expect(hash[:message_deduplication_id]).to_not be
        expect(hash[:delay_seconds]).to eq(delay)
      end

      expect(Shoryuken).to receive(:register_worker).with(job.queue_name, described_class::JobWrapper)

      # need to figure out what to require Time.current and N.minutes to remove the stub
      allow(subject).to receive(:calculate_delay).and_return(delay)

      subject.enqueue_at(job, nil)
    end
  end
end
