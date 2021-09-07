# frozen_string_literal: true

module Recorder
  module Rails
    class Railtie < Rails::Railtie
      initializer 'recorder.configure' do |_app|
        require 'recorder/sidekiq/revisions_worker' if defined?(Sidekiq)
      end
    end
  end
end
