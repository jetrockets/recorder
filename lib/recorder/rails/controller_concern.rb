# frozen_string_literal: true

module Recorder
  module Rails
    # Extensions to rails controllers. Provides convenient ways to pass certain
    # information to the model layer, with `recorder_meta`.
    module ControllerConcern
      def self.included(base)
        base.before_action :set_recorder_info
      end

      protected

      # Returns the id of the user responsible for any changes that occur:
      # `current_user`'s `id`, or `current_user` itself when it is the id.
      #
      # Override this method in your controller to call a different
      # method, e.g. `current_person`, or anything you like.
      def recorder_user_id
        return unless respond_to?(:current_user, true)

        user = current_user
        user.respond_to?(:id) ? user.id : user
      end

      def recorder_info
        {
          user_id: recorder_user_id,
          ip: request.remote_ip,
          action_date: Date.current,
          meta: recorder_meta
        }
      end

      # Override this method in your controller to return a hash of any
      # information you need.
      def recorder_meta
        nil
      end

      # Tells Recorder any information from the controller you want to store
      # alongside any changes that occur.
      def set_recorder_info
        ::Recorder.info = recorder_info
      end
    end
  end
end
