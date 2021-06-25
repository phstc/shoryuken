module Shoryuken
  module Worker
    class InlineExecutor
      class << self
        def perform_async(worker_class, body, options = {})
          body = JSON.dump(body) if body.is_a?(Hash)
          queue_name = options.delete(:queue) || worker_class.get_shoryuken_options['queue']

          sqs_msg = OpenStruct.new(
            body: body,
            attributes: nil,
            md5_of_body: nil,
            md5_of_message_attributes: nil,
            message_attributes: nil,
            message_id: nil,
            receipt_handle: nil,
            delete: nil,
            queue_name: queue_name
          )

          call(worker_class, sqs_msg)
        end

        def perform_in(worker_class, _interval, body, options = {})
          worker_class.perform_async(body, options)
        end

        private

        def call(worker_class, sqs_msg)
          worker = worker_class.new
          worker_class.server_middleware.invoke(worker, 'default', sqs_msg, sqs_msg.body) do
            worker.perform(*perform_arguments(worker_class, sqs_msg))
          end
        end

        def perform_arguments(worker_class, sqs_msg)
          parsed_body = BodyParser.parse(worker_class, sqs_msg)
          batch = worker_class.shoryuken_options_hash['batch']
          batch ? [[sqs_msg], [parsed_body]] : [sqs_msg, parsed_body]
        end
      end
    end
  end
end
