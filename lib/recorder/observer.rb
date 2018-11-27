require 'recorder/tape'
require 'active_support/concern'

module Recorder
  module Observer
    extend ::ActiveSupport::Concern

    included do

      #   def create_async(params)
      #     Recorder::Sidekiq::RevisionsWorker.perform_async(
      #       proxy_association.owner.class.to_s,
      #       proxy_association.owner.id,
      #       params
      #     )
      #   end
      # end
    end

    def recorder_dirty?
      return @recorder_dirty if defined?(@recorder_dirty)
      true
    end

    module ClassMethods
      attr_reader :recorder_options

      def recorder(options = {})
        @recorder_options = options.reverse_merge(
          class_name: 'Recorder::Revision'
        )

        # define_method 'recorder_options' do
        #   options
        # end

        has_many :revisions, :class_name => recorder_options[:class_name], :inverse_of => :item, :as => :item

        after_create do
          if self.recorder_dirty?
            Recorder::Tape.new(self).record_create
          end
        end

        after_update do
          puts "!!!"
          puts  self.recorder_dirty?
          if self.recorder_dirty?
            puts "!DIRTY"
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
