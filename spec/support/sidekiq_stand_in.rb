# frozen_string_literal: true

# `Recorder::Sidekiq::RevisionsWorker` does `include ::Sidekiq::Worker` in its
# class body, and the gem declares no Sidekiq dependency. This stand-in supplies
# the two class methods the worker and its callers use, so the worker class
# loads on every run and a `class_double` of it verifies against something real.
#
# `::Sidekiq` is removed once the worker has loaded. The include has already
# taken effect, so the worker keeps the methods while `defined?(Sidekiq)` reads
# false for the rest of the suite — `Recorder::Rails::Railtie` branches on that
# constant, and the answer it gets has to be the truthful one.
stand_in = !defined?(::Sidekiq)

if stand_in
  module Sidekiq
    module Worker
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def sidekiq_options(options = {})
          options
        end

        def perform_in(interval, *args)
        end
      end
    end
  end
end

require 'recorder/sidekiq/revisions_worker'

Object.send(:remove_const, :Sidekiq) if stand_in
