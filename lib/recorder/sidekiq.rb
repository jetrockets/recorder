# frozen_string_literal: true

module Recorder
  # Raised when a revision is asked to be written asynchronously but Sidekiq is
  # not available. Sidekiq is an optional dependency: it appears nowhere in the
  # gemspec, and the worker is only loaded when the host app brought it along.
  class SidekiqNotAvailable < StandardError; end

  class << self
    # Returns `true` if the async write path can be taken.
    #
    # Gates on `::Sidekiq` rather than on the worker constant: `Bundler.require`
    # runs before both the railtie initializer and model loading, so this is
    # already answerable when a `recorder` macro or an initializer runs, while
    # the worker may not be required yet.
    # @api private
    def sidekiq_available?
      defined?(::Sidekiq) ? true : false
    end

    # Loads the worker on demand. The railtie requires it eagerly when Sidekiq
    # is present; this covers the non-Rails and early-boot cases.
    # @api private
    def sidekiq_worker
      require 'recorder/sidekiq/revisions_worker'
      Recorder::Sidekiq::RevisionsWorker
    end

    # Fails fast, at declaration time, on `async: true` without Sidekiq. Without
    # this the app raises `NameError: uninitialized constant Recorder::Sidekiq`
    # on the first save instead, pointing at the gem rather than at the line
    # that asked for it.
    # @api private
    def assert_async_available!(async, subject)
      return unless async
      return if sidekiq_available?

      raise SidekiqNotAvailable,
        "#{subject}, but Sidekiq is not loaded. Add `sidekiq` to your Gemfile, " \
        'or record synchronously instead.'
    end
  end
end
