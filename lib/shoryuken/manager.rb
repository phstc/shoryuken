require 'shoryuken/processor'
require 'shoryuken/polling'
require 'shoryuken/fetcher'

module Shoryuken
  class Manager
    include Celluloid
    include Util

    attr_accessor :fetcher

    trap_exit :processor_died

    def initialize(condvar)
      @count  = Shoryuken.options[:concurrency] || 25
      @polling_strategy = Shoryuken.options[:polling_strategy].new(Shoryuken.queues)
      @finished = condvar

      @done = false

      @busy  = []
      @ready = @count.times.map { build_processor }
      @threads = {}
    end

    def start
      logger.info { 'Starting' }

      dispatch
    end

    def stop(options = {})
      watchdog('Manager#stop died') do
        @done = true

        if (callback = Shoryuken.stop_callback)
          logger.info { 'Calling Shoryuken.on_stop block' }
          callback.call
        end

        @fetcher.terminate if @fetcher.alive?

        logger.info { "Shutting down #{@ready.size} quiet workers" }

        @ready.each do |processor|
          processor.terminate if processor.alive?
        end
        @ready.clear

        return after(0) { @finished.signal } if @busy.empty?

        if options[:shutdown]
          hard_shutdown_in(options[:timeout])
        else
          soft_shutdown(options[:timeout])
        end
      end
    end

    def processor_done(queue, processor)
      watchdog('Manager#processor_done died') do
        logger.debug { "Process done for '#{queue}'" }

        @threads.delete(processor.object_id)
        @busy.delete processor

        if stopped?
          processor.terminate if processor.alive?
        else
          @ready << processor
        end
      end
    end

    def processor_died(processor, reason)
      watchdog("Manager#processor_died died") do
        logger.error { "Process died, reason: #{reason}" unless reason.to_s.empty? }

        @threads.delete(processor.object_id)
        @busy.delete processor

        unless stopped?
          @ready << build_processor
        end
      end
    end

    def stopped?
      @done
    end

    def assign(queue, sqs_msg)
      watchdog('Manager#assign died') do
        logger.debug { "Assigning #{sqs_msg.message_id}" }

        processor = @ready.pop
        @busy << processor

        processor.async.process(queue, sqs_msg)
      end
    end

    def messages_present(queue)
      watchdog('Manager#messages_present died') do
        @polling_strategy.messages_present(queue)
      end
    end

    def queue_empty(queue)
      return if delay <= 0

      logger.debug { "Pausing '#{queue}' for #{delay} seconds, because it's empty" }

      @polling_strategy.pause(queue)

      after(delay) { async.restart_queue!(queue) }
    end


    def dispatch
      return if stopped?

      logger.debug { "Ready: #{@ready.size}, Busy: #{@busy.size}, Active Queues: #{@polling_strategy.active_queues}" }

      if @ready.empty?
        logger.debug { 'Pausing fetcher, because all processors are busy' }

        after(1) { dispatch }

        return
      end

      if (queue = next_queue)
        @fetcher.async.fetch(queue, @ready.size)
      else
        logger.debug { 'Pausing fetcher, because all queues are paused' }

        @fetcher_paused = true
      end
    end

    def real_thread(proxy_id, thr)
      @threads[proxy_id] = thr
    end

    private

    def delay
      Shoryuken.options[:delay].to_f
    end

    def build_processor
      processor = Processor.new_link(current_actor)
      processor.proxy_id = processor.object_id
      processor
    end

    def restart_queue!(queue)
      return if stopped?

      @polling_strategy.restart(queue)

      if @fetcher_paused
        logger.debug { 'Restarting fetcher' }

        @fetcher_paused = false

        dispatch
      end
    end

    def next_queue
      # get/remove the first queue in the list
      queue = @polling_strategy.next_queue

      return nil unless queue

      if queue && (!defined?(::ActiveJob) && Shoryuken.worker_registry.workers(queue.name).empty?)
        # when no worker registered pause the queue to avoid endless recursion
        logger.debug { "Pausing '#{queue}' for #{delay} seconds, because no workers registered" }

        @polling_strategy.pause(queue)

        after(delay) { async.restart_queue!(queue) }

        queue = next_queue
      end

      queue
    end

    def soft_shutdown(delay)
      logger.info { "Waiting for #{@busy.size} busy workers" }

      if @busy.size > 0
        after(delay) { soft_shutdown(delay) }
      else
        @finished.signal
      end
    end

    def hard_shutdown_in(delay)
      logger.info { "Waiting for #{@busy.size} busy workers" }
      logger.info { "Pausing up to #{delay} seconds to allow workers to finish..." }

      after(delay) do
        watchdog('Manager#hard_shutdown_in died') do
          if @busy.size > 0
            logger.info { "Hard shutting down #{@busy.size} busy workers" }

            @busy.each do |processor|
              if processor.alive? && t = @threads.delete(processor.object_id)
                t.raise Shutdown
              end
            end
          end

          @finished.signal
        end
      end
    end
  end
end
