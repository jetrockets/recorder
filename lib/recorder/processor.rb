module Recorder
  class Processor
    attr_reader :strategy

    def initialize(strategy)
      @strategy = strategy
    end

    def set_strategy(strategy)
      @strategy.finalize!
      @strategy = strategy
    end

    class << self

      def process_with(strategy)
        old_strategy = instance.strategy
        instance.set_strategy(strategy)
        yield
        instance.set_strategy(old_strategy)
      end

      def set_strategy(strategy)
        instance.set_strategy(strategy)
      end

      def process(item, params)
        instance.strategy.persist(item, params)
      end

      private

      def instance
        @instance ||= Recorder::Processor.new(Recorder::Strategy::SyncSave.new)
      end
    end
  end
end