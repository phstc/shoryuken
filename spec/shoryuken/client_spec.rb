require 'spec_helper'

describe Shoryuken::Client do
  let(:sqs) { Aws::SQS::Client.new stub_responses: true }
  let(:queue_name) { 'shoryuken' }
  let(:queue_url) { 'https://eu-west-1.amazonaws.com:6059/123456789012/shoryuken' }

  before do
    described_class.sqs = sqs
  end

  describe '.queue' do
    it 'memoizes queues' do
      sqs.stub_responses(:get_queue_url, { queue_url: queue_url }, { queue_url: 'xyz' })

      expect(Shoryuken::Client.queues(queue_name).url).to eq queue_url
      expect(Shoryuken::Client.queues(queue_name).url).to eq queue_url
    end
  end
end
