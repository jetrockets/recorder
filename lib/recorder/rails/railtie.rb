# frozen_string_literal: true

module Recorder
  module Rails
    class Railtie < ::Rails::Railtie
      initializer 'recorder.deprecator' do |app|
        app.deprecators[:recorder] = Recorder.deprecator if app.respond_to?(:deprecators)
      end
    end
  end
end
