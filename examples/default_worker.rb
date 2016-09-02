class DefaultWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'default', auto_delete: true

  def perform(sqs_msg, body)
    Shoryuken.logger.info("Received message: '#{body}'")
  end
end
