module Shoryuken
  module Worker
    class FakeExecutor
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
        end

        def perform_in(worker_class, _interval, body, options = {})
          worker_class.perform_async(body, options)
        end
      end
    end
  end
end
