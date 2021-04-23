module Shoryuken
  class Options
    DEFAULTS = {
      concurrency: 25,
      queues: [],
      aws: {},
      delay: 0.0,
      timeout: 8,
      lifecycle_events: {
        startup: [],
        dispatch: [],
        quiet: [],
        shutdown: []
      }
    }.freeze

    attr_accessor :active_job_queue_name_prefixing, :cache_visibility_timeout, :groups,
                  :launcher_executor,
                  :start_callback, :stop_callback, :worker_executor, :worker_registry
    attr_writer :default_worker_options, :sqs_client
    attr_reader :sqs_client_receive_message_opts

    def initialize
      self.groups = {}
      self.worker_registry = DefaultWorkerRegistry.new
      self.active_job_queue_name_prefixing = false
      self.worker_executor = Worker::DefaultExecutor
      self.cache_visibility_timeout = false
      # this is needed for keeping backward compatibility
      @sqs_client_receive_message_opts ||= {}
    end

    def active_job?
      defined?(::ActiveJob)
    end

    def add_group(group, concurrency = nil, delay: nil, polling_strategy: 'WeightedRoundRobin')
      concurrency ||= options[:concurrency]
      delay ||= options[:delay]
      polling_strategy ||= polling_strategy

      groups[group] ||= {
        concurrency: concurrency,
        delay: delay,
        queues: [],
        polling_strategy: polling_strategy
      }
    end

    def add_queue(queue, weight, group)
      weight.times do
        groups[group][:queues] << queue
      end
    end

    def ungrouped_queues
      groups.values.flat_map { |options| options[:queues] }
    end

    def polling_strategy(group)
      strategy = \
        if group == 'default'
          options.to_h[:polling_strategy]
        elsif options[:groups].nil?
          # checks given group for polling strategy
          groups.to_h[group].to_h[:polling_strategy]
        else
          # checks option hash for polling strategy
          options[:groups].to_h[group].to_h[:polling_strategy]
        end

      case strategy
      when 'WeightedRoundRobin', nil # Default case
        Polling::WeightedRoundRobin
      when 'StrictPriority'
        Polling::StrictPriority
      when Class
        strategy
      else
        raise ArgumentError, "#{strategy} is not a valid polling_strategy"
      end
    end

    def delay(group)
      groups[group].to_h.fetch(:delay, options[:delay]).to_f
    end

    def sqs_client
      @sqs_client ||= Aws::SQS::Client.new
    end

    def sqs_client_receive_message_opts=(sqs_client_receive_message_opts)
      @sqs_client_receive_message_opts['default'] = sqs_client_receive_message_opts
    end

    def options
      @options ||= DEFAULTS.dup
    end

    def logger
      Shoryuken::Logging.logger
    end

    def register_worker(*args)
      worker_registry.register_worker(*args)
    end

    def configure_server
      yield self if server?
    end

    def server_middleware
      @_server_chain ||= default_server_middleware
      yield @_server_chain if block_given?
      @_server_chain
    end

    def configure_client
      yield self unless server?
    end

    def client_middleware
      @_client_chain ||= default_client_middleware
      yield @_client_chain if block_given?
      @_client_chain
    end

    def default_worker_options
      @default_worker_options ||= {
        'queue' => 'default',
        'delete' => false,
        'auto_delete' => false,
        'auto_visibility_timeout' => false,
        'retry_intervals' => nil,
        'batch' => false
      }
    end

    def on_start(&block)
      self.start_callback = block
    end

    def on_stop(&block)
      self.stop_callback = block
    end

    # Register a block to run at a point in the Shoryuken lifecycle.
    # :startup, :quiet or :shutdown are valid events.
    #
    #   Shoryuken.configure_server do |config|
    #     config.on(:shutdown) do
    #       puts "Goodbye cruel world!"
    #     end
    #   end
    def on(event, &block)
      fail ArgumentError, "Symbols only please: #{event}" unless event.is_a?(Symbol)
      fail ArgumentError, "Invalid event name: #{event}" unless options[:lifecycle_events].key?(event)

      options[:lifecycle_events][event] << block
    end

    def server?
      defined?(Shoryuken::CLI)
    end

    def cache_visibility_timeout?
      @cache_visibility_timeout
    end

    def active_job_queue_name_prefixing?
      @active_job_queue_name_prefixing
    end

    private

    def default_server_middleware
      Middleware::Chain.new do |m|
        m.add Middleware::Server::Timing
        m.add Middleware::Server::ExponentialBackoffRetry
        m.add Middleware::Server::AutoDelete
        m.add Middleware::Server::AutoExtendVisibility
        if defined?(::ActiveRecord::Base)
          require 'shoryuken/middleware/server/active_record'
          m.add Middleware::Server::ActiveRecord
        end
      end
    end

    def default_client_middleware
      Middleware::Chain.new
    end
  end
end
