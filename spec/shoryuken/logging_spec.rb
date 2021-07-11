require "spec_helper"

RSpec.describe Shoryuken::Logging do
  class self::MyLogger < Logger
    def initialize(output)
      super(output)
      @context = []
    end

    def info(msg)
      super(@context.join(" ") + " " + msg)
    end

    def add_context(msg)
      @context << msg
    end

    def clear_context
      @context = nil
    end
  end
  let(:output) do
    StringIO.new
  end
  context ".with_context" do
    context "with customer logger" do
      let(:formatter) do
        double('my_formatter')
      end
      let(:custom_logger) do
        self.class::MyLogger.new(output)
      end
      before(:each) do
        Shoryuken::Logging.logger = custom_logger
      end
      it "can attach context if logger implements #update_log_content" do
        my_context = "my_context"
        my_msg = "My log msg"
        Shoryuken::Logging.with_context(my_context) do
          custom_logger.info my_msg
        end

        output.rewind
        msg = output.read
        expect(msg).to include(my_context)
        expect(my_msg).to include(my_msg)
      end

      it "cleans up via #clear_context" do
        expect(custom_logger).to receive(:clear_context!)
        Shoryuken::Logging.with_context("context") do
          custom_logger.info "some msg"
        end
      end
    end

    context "built in logger" do
      it "appends the context" do
        my_context = "my_context"
        my_msg = "My log msg"
        Shoryuken::Logging.initialize_logger(output)
        Shoryuken::Logging.with_context(my_context) do
          Shoryuken::Logging.logger.info my_msg
        end

        output.rewind
        msg = output.read
        expect(msg).to include(my_context)
        expect(my_msg).to include(my_msg)
      end

      it "lets you nest context" do
        my_context = "my_context"
        my_context2 = "aother context"
        my_msg = "My log msg"
        Shoryuken::Logging.initialize_logger(output)
        Shoryuken::Logging.with_context(my_context) do
          Shoryuken::Logging.with_context(my_context2) do
            Shoryuken::Logging.logger.info my_msg
          end
        end

        output.rewind
        msg = output.read
        expect(msg).to include(my_context)
        expect(msg).to include(my_context2)
        expect(my_msg).to include(my_msg)
      end

      it "cleans up" do
        Shoryuken::Logging.with_context("anything") do
          Shoryuken::Logging.logger.info "anything"
        end
        expect(Thread.current[:shoryuken_context]).to be_nil
      end
    end
  end
end
