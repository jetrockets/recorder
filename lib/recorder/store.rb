# frozen_string_literal: true

require 'request_store'

module Recorder
  # The request info and the switch `Recorder::Manager` toggles. Each fiber
  # keeps its own in RequestStore, whose middleware clears it when a request
  # ends.
  #
  # On Ruby 3.2+, a fiber that has none starts from the one that created it,
  # through inheritable fiber storage: with the switch as it was when the
  # fiber was created, and with a copy of the info taken when the fiber first
  # uses the store. A thread starts with a store of its own, so a thread that
  # a pool spawns during a request carries nothing into later work.
  class Store
    State = Struct.new(:enabled, :params)
    private_constant :State

    def params
      state.params
    end

    def recorder_enabled!
      switch(true)
    end

    def recorder_disabled!
      switch(false)
    end

    def recorder_enabled?
      state.enabled
    end

    private

    def state
      current = RequestStore.store[:recorder] ||= inherited || State.new(true, {})
      pass_on(current)
      current
    end

    def switch(enabled)
      current = state
      current.enabled = enabled
      pass_on(current)
      enabled
    end

    if Fiber.respond_to?(:[])
      FIBER_KEY = :recorder_store
      private_constant :FIBER_KEY

      # What a fiber created now starts from: this fiber's state, with the
      # switch as it is at this moment.
      Inheritance = Struct.new(:state, :enabled, :thread, :fiber)
      private_constant :Inheritance

      # Takes up what the creating fiber passed on, unless it was passed on
      # in another thread, or is this fiber's own and RequestStore has since
      # lost the state behind it.
      def inherited
        from = Fiber[FIBER_KEY]
        return unless from&.thread.equal?(Thread.current) && !from.fiber.equal?(Fiber.current)

        State.new(from.enabled, from.state.params.dup)
      end

      def pass_on(current)
        from = Fiber[FIBER_KEY]
        return if from&.state.equal?(current) && from.enabled == current.enabled && from.fiber.equal?(Fiber.current)

        Fiber[FIBER_KEY] = Inheritance.new(current, current.enabled, Thread.current, Fiber.current).freeze
      end

      # RequestStore.clear! and RequestStore.store= replace the current
      # fiber's state, so what the fiber passes on to new fibers goes too.
      module ForgetOnReset
        def clear!
          Fiber[FIBER_KEY] = nil
          super
        end

        def store=(store)
          Fiber[FIBER_KEY] = nil
          super
        end
      end
      private_constant :ForgetOnReset

      RequestStore.singleton_class.prepend(ForgetOnReset)
    else
      # simplecov:disable Ruby 3.0 and 3.1 only; the suite runs on them without coverage
      def inherited
      end

      def pass_on(_current)
      end
      # simplecov:enable
    end
  end
end
