module Shoryuken
  class Processor
    include Util

    attr_reader :queue, :sqs_msg

    def self.process(queue, sqs_msg)
      new(queue, sqs_msg).process
    end

    def initialize(queue, sqs_msg)
      @queue   = queue
      @sqs_msg = sqs_msg
    end

    def process
      return logger.error { "No worker found for #{queue}" } unless worker

      Shoryuken::Logging.with_context("#{worker_name(worker.class, sqs_msg, body)}/#{queue}/#{sqs_msg.message_id}") do
        worker.class.server_middleware.invoke(worker, queue, sqs_msg, body) do |_worker, _queue, sqs_msg, body|
          worker.perform(sqs_msg, body)
        end
      end
    rescue Exception => ex
      logger.error { "Processor failed: #{ex.message}" }
      logger.error { ex.backtrace.join("\n") } unless ex.backtrace.nil?

      raise
    end

    private

    def worker
      @_worker ||= Shoryuken.worker_registry.fetch_worker(queue, sqs_msg)
    end

    def worker_class
      worker.class
    end

    def body
      @_body ||= sqs_msg.is_a?(Array) ? sqs_msg.map(&method(:parse_body)) : parse_body(sqs_msg)
    end

    def parse_body(sqs_msg)
      BodyParser.parse(worker_class, sqs_msg)
    end
  end
end
