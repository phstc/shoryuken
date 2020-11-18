module Shoryuken
  class EnvironmentLoader
    attr_reader :options

    def self.setup_options(options)
      instance = new(options)
      instance.setup_options
      instance
    end

    def self.load_for_rails_console
      instance = setup_options(config_file: (Rails.root + 'config' + 'shoryuken.yml'))
      instance.load
    end

    def initialize(options)
      @options = options
    end

    def setup_options
      initialize_options
      initialize_logger
    end

    def load
      load_rails if Shoryuken.options[:rails]
      prefix_active_job_queue_names
      parse_queues
      require_workers
      validate_queues
      validate_workers
    end

    private

    def initialize_options
      Shoryuken.options.merge!(config_file_options)
      Shoryuken.options.merge!(options)
    end

    def config_file_options
      return {} unless (path = options[:config_file])

      fail ArgumentError, "The supplied config file #{path} does not exist" unless File.exist?(path)

      if (result = YAML.load(ERB.new(IO.read(path)).result))
        result.deep_symbolize_keys
      else
        {}
      end
    end

    def initialize_logger
      Shoryuken::Logging.initialize_logger(Shoryuken.options[:logfile]) if Shoryuken.options[:logfile]
      Shoryuken.logger.level = Logger::DEBUG if Shoryuken.options[:verbose]
    end

    def load_rails
      # Adapted from: https://github.com/mperham/sidekiq/blob/master/lib/sidekiq/cli.rb

      require 'rails'
      if ::Rails::VERSION::MAJOR < 4
        require File.expand_path('config/environment.rb')
        ::Rails.application.eager_load!
      else
        # Painful contortions, see 1791 for discussion
        require File.expand_path('config/application.rb')
        if ::Rails::VERSION::MAJOR == 4
          ::Rails::Application.initializer 'shoryuken.eager_load' do
            ::Rails.application.config.eager_load = true
          end
        end
        ::Rails::Application.initializer 'shoryuken.set_reloader_hook' do |app|
          Shoryuken.reloader = proc do |&block|
            app.reloader.wrap do
              block.call
            end
          end
        end
        require 'shoryuken/extensions/active_job_adapter' if Shoryuken.active_job?
        require File.expand_path('config/environment.rb')
      end
    end

    def prefix_active_job_queue_name(queue_name, weight)
      queue_name_prefix = ::ActiveJob::Base.queue_name_prefix
      queue_name_delimiter = ::ActiveJob::Base.queue_name_delimiter

      # See https://github.com/rails/rails/blob/master/activejob/lib/active_job/queue_name.rb#L27
      name_parts = [queue_name_prefix.presence, queue_name]
      prefixed_queue_name = name_parts.compact.join(queue_name_delimiter)
      [prefixed_queue_name, weight]
    end

    def prefix_active_job_queue_names
      return unless Shoryuken.active_job?
      return unless Shoryuken.active_job_queue_name_prefixing?

      Shoryuken.options[:queues].to_a.map! do |queue_name, weight|
        prefix_active_job_queue_name(queue_name, weight)
      end

      Shoryuken.options[:groups].to_a.map! do |group, options|
        if options[:queues]
          options[:queues].map! do |queue_name, weight|
            prefix_active_job_queue_name(queue_name, weight)
          end
        end

        [group, options]
      end
    end

    def parse_queue(queue, weight, group)
      Shoryuken.add_queue(queue, [weight.to_i, 1].max, group)
    end

    def parse_queues
      if Shoryuken.options[:queues].to_a.any?
        Shoryuken.add_group('default', Shoryuken.options[:concurrency])

        Shoryuken.options[:queues].to_a.each do |queue, weight|
          parse_queue(queue, weight, 'default')
        end
      end

      Shoryuken.options[:groups].to_a.each do |group, options|
        Shoryuken.add_group(group, options[:concurrency], delay: options[:delay])

        options[:queues].to_a.each do |queue, weight|
          parse_queue(queue, weight, group)
        end
      end
    end

    def require_workers
      required = Shoryuken.options[:require]

      return unless required

      if File.directory?(required)
        Dir[File.join(required, '**', '*.rb')].each(&method(:require))
      else
        require required
      end
    end

    def validate_queues
      return Shoryuken.logger.warn { 'No queues supplied' } if Shoryuken.ungrouped_queues.empty?

      non_existent_queues = []

      Shoryuken.ungrouped_queues.uniq.each do |queue|
        begin
          Shoryuken::Client.queues(queue)
        rescue Aws::Errors::NoSuchEndpointError, Aws::SQS::Errors::NonExistentQueue
          non_existent_queues << queue
        end
      end

      return if non_existent_queues.none?

      fail(
        ArgumentError,
        "The specified queue(s) #{non_existent_queues.join(', ')} do not exist.\nTry 'shoryuken sqs create QUEUE-NAME' for creating a queue with default settings"
      )
    end

    def validate_workers
      return if Shoryuken.active_job?

      all_queues = Shoryuken.ungrouped_queues
      queues_with_workers = Shoryuken.worker_registry.queues

      (all_queues - queues_with_workers).each do |queue|
        Shoryuken.logger.warn { "No worker supplied for #{queue}" }
      end
    end
  end
end
