require 'json'

module Shoryuken
  class Processor
    include Celluloid
    include Util

    def initialize(manager)
      @manager = manager
      @message_visibility = MessageVisiblity.new_link
    end

    attr_accessor :proxy_id

    def process(queue, sqs_msg)
      @manager.async.real_thread(proxy_id, Thread.current)

      worker = Shoryuken.worker_registry.fetch_worker(queue, sqs_msg)

      timer = @message_visibility.auto_increment(queue, sqs_msg, worker.class)

      begin
        body = get_body(worker.class, sqs_msg)

        worker.class.server_middleware.invoke(worker, queue, sqs_msg, body) do
          worker.perform(sqs_msg, body)
        end

        @manager.async.processor_done(queue, current_actor)
      ensure
        timer.cancel if timer
      end
    end

    private

    def get_body(worker_class, sqs_msg)
      if sqs_msg.is_a? Array
        sqs_msg.map { |m| parse_body(worker_class, m) }
      else
        parse_body(worker_class, sqs_msg)
      end
    end

    def parse_body(worker_class, sqs_msg)
      body_parser = worker_class.get_shoryuken_options['body_parser']

      case body_parser
      when :json
        JSON.parse(sqs_msg.body)
      when Proc
        body_parser.call(sqs_msg)
      when :text, nil
        sqs_msg.body
      else
        if body_parser.respond_to?(:parse)
          # JSON.parse
          body_parser.parse(sqs_msg.body)
        elsif body_parser.respond_to?(:load)
          # see https://github.com/phstc/shoryuken/pull/91
          # JSON.load
          body_parser.load(sqs_msg.body)
        end
      end
    rescue => e
      logger.error "Error parsing the message body: #{e.message}\nbody_parser: #{body_parser}\nsqs_msg.body: #{sqs_msg.body}"
      nil
    end
  end

  class MessageVisiblity
    include Celluloid
    include Util

    def auto_increment(queue, sqs_msg, worker_class)
      if worker_class.auto_visibility_timeout?
        queue_visibility_timeout = Shoryuken::Client.queues(queue).visibility_timeout
        timer = every(queue_visibility_timeout - 5) do
          begin
            logger.debug "Extending message #{worker_name(worker_class, sqs_msg)}/#{queue}/#{sqs_msg.message_id} visibility timeout by #{queue_visibility_timeout}s."

            sqs_msg.visibility_timeout = queue_visibility_timeout
          rescue => e
            logger.error "Could not auto extend the message #{worker_class}/#{queue}/#{sqs_msg.message_id} visibility timeout. Error: #{e.message}"
          end
        end
      end

      timer
    end
  end
end
