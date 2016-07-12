class Recorder::Rails::Railtie < Rails::Railtie
  initializer "recorder.configure" do |app|
    if defined?(Sidekiq)
      require 'recorder/sidekiq/revisions_worker'
    end
  end
end
