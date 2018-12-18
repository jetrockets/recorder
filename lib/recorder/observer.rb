require 'recorder/tape'
require 'recorder/strategy/sync_save'
require 'recorder/strategy/async_save'
require 'recorder/strategy/batch_sync_save'
require 'active_support/concern'

module Recorder
  module Observer
    extend ::ActiveSupport::Concern

    included do
      has_many :revisions, :class_name => '::Recorder::Revision', :inverse_of => :item, :as => :item do
        def create_async(params)
          Recorder::Sidekiq::RevisionsWorker.perform_async(
            proxy_association.owner.class.to_s,
            proxy_association.owner.id,
            params
          )
        end
      end
    end

    def recorder_dirty?
      return @recorder_dirty if defined?(@recorder_dirty)
      true
    end

    module ClassMethods
      def recorder(options = {})
        define_method :recorder_options do
          options
        end

        define_singleton_method :recorder_strategy do
          @recorder_strategy ||= if options[:strategy]
            options[:strategy].new(options[:strategy_opts] || {})
          else
            if options[:async]
              Recorder::Strategy::AsyncSave.new
            else
              Recorder::Strategy::SyncSave.new
            end
          end
        end

        define_singleton_method :recorder_finalize! do
          if options[:strategy]
            options[:strategy].finalize!
          end
        end

        after_create do
          if self.recorder_dirty?
            Recorder::Tape.new(self).record_create
          end
        end

        after_update do
          if self.recorder_dirty?
            Recorder::Tape.new(self).record_update
          end
        end

        after_destroy do
          if self.recorder_dirty?
            Recorder::Tape.new(self).record_destroy
          end
        end
      end
    end
  end
end
