module Shoryuken
  # Middleware is code configured to run before/after
  # a message is processed.  It is patterned after Rack
  # middleware. Middleware exists for the server
  # side (when jobs are actually processed).
  #
  # To modify middleware for the server, just call
  # with another block:
  #
  # Shoryuken.configure_server do |config|
  #   config.server_middleware do |chain|
  #     chain.add MyServerHook
  #     chain.remove ActiveRecord
  #   end
  # end
  #
  # To insert immediately preceding another entry:
  #
  # Shoryuken.configure_server do |config|
  #   config.server_middleware do |chain|
  #     chain.insert_before ActiveRecord, MyServerHook
  #   end
  # end
  #
  # To insert immediately after another entry:
  #
  # Shoryuken.configure_server do |config|
  #   config.server_middleware do |chain|
  #     chain.insert_after ActiveRecord, MyServerHook
  #   end
  # end
  #
  # This is an example of a minimal server middleware:
  #
  # class MyServerHook
  #   def call(worker_instance, queue, sqs_msg)
  #     puts 'Before work'
  #     yield
  #     puts 'After work'
  #   end
  # end
  #
  module Middleware
    class Chain
      attr_reader :entries

      def initialize
        @entries = []
        yield self if block_given?
      end

      def dup
        self.class.new.tap { |new_chain| new_chain.entries.replace(entries) }
      end

      def remove(klass)
        entries.delete_if { |entry| entry.klass == klass }
      end

      def add(klass, *args)
        entries << Entry.new(klass, *args) unless exists?(klass)
      end

      def prepend(klass, *args)
        entries.insert(0, Entry.new(klass, *args)) unless exists?(klass)
      end

      def insert_before(oldklass, newklass, *args)
        i = entries.index { |entry| entry.klass == newklass }
        new_entry = i.nil? ? Entry.new(newklass, *args) : entries.delete_at(i)
        i = entries.find_index { |entry| entry.klass == oldklass } || 0
        entries.insert(i, new_entry)
      end

      def insert_after(oldklass, newklass, *args)
        i = entries.index { |entry| entry.klass == newklass }
        new_entry = i.nil? ? Entry.new(newklass, *args) : entries.delete_at(i)
        i = entries.find_index { |entry| entry.klass == oldklass } || entries.count - 1
        entries.insert(i + 1, new_entry)
      end

      def exists?(klass)
        entries.any? { |entry| entry.klass == klass }
      end

      def retrieve
        entries.map(&:make_new)
      end

      def clear
        entries.clear
      end

      def invoke(*args, &final_action)
        chain = retrieve.dup
        traverse_chain = lambda do |*modified_args|
          next_args = modified_args.any? ? modified_args : args

          if chain.empty?
            final_action.call(*next_args)
          else
            chain.shift.call(*next_args, &traverse_chain)
          end
        end
        traverse_chain.call
      end
    end

    class Entry
      attr_reader :klass

      def initialize(klass, *args)
        @klass = klass
        @args  = args
      end

      def make_new
        @klass.new(*@args)
      end
    end
  end
end
