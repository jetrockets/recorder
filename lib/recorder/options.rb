# frozen_string_literal: true

require 'active_support/core_ext/hash/keys'

module Recorder
  # Checks the options passed to `.recorder` and stores them as a frozen,
  # symbol-keyed copy.
  # @api private
  module Options
    KEYS = %i[ignore only associations changes if unless].freeze
    ASSOCIATION_KEYS = %i[ignore only].freeze
    # What a class whose hierarchy never called `.recorder` reports.
    NONE = {}.freeze
    # Asynchronous recording was removed in 2.0.0.
    REMOVED_KEYS = %i[async delay].freeze

    module_function

    # @raise [ArgumentError] for options that are not a Hash, an unknown key,
    #   or an option `Recorder::Tape::Data` or the callbacks cannot apply
    def normalize(options)
      options = symbolize(options, '`recorder`')
      removed = options.keys & REMOVED_KEYS
      if removed.any?
        raise ArgumentError, "`recorder` does not take #{removed.map { |key| "`#{key}:`" }.join(" or ")}: " \
          'asynchronous recording was removed in 2.0.0, and every revision is written in the save transaction.'
      end

      assert_known_keys(options, KEYS, '`recorder`')
      Recorder::Tape::Data.validate_changes_option!(options[:changes])
      %i[if unless].each { |key| validate_condition(key, options[key]) if options.key?(key) }
      options[:associations] = normalize_associations(options[:associations]) if options.key?(:associations)

      deep_freeze(options)
    end

    def validate_condition(key, condition)
      return if condition.nil? || condition.is_a?(Symbol) || condition.is_a?(Proc)

      raise ArgumentError, "`#{key}:` expects a method name as a Symbol or a Proc, got #{condition.inspect}"
    end

    # Takes a Hash of association name => options, or an Array of names, and
    # symbolizes the names either way.
    def normalize_associations(associations)
      return if associations.nil?
      return associations.map { |name| association_name(name) } if associations.is_a?(Array)
      unless associations.is_a?(Hash)
        raise ArgumentError, "`associations:` expects a Hash or an Array of names, got #{associations.inspect}"
      end

      associations.each_with_object({}) do |(name, options), normalized|
        name = association_name(name)
        raise ArgumentError, "`associations:` names `#{name}` both as a Symbol and as a String" if normalized.key?(name)

        normalized[name] = association_options(name, options)
      end
    end

    def association_name(name)
      return name.to_sym if name.is_a?(Symbol) || name.is_a?(String)

      raise ArgumentError, "`associations:` expects association names as Symbols or Strings, got #{name.inspect}"
    end

    def association_options(name, options)
      return if options.nil?

      owner = "`associations[#{name.inspect}]`"
      options = symbolize(options, owner)
      assert_known_keys(options, ASSOCIATION_KEYS, owner)
      options
    end

    def assert_known_keys(options, keys, owner)
      unknown = options.keys - keys
      return if unknown.empty?

      raise ArgumentError, "Unknown key#{"s" if unknown.many?}: #{unknown.map(&:inspect).join(", ")} in #{owner}. " \
        "Valid keys are: #{keys.map(&:inspect).join(", ")}"
    end

    def symbolize(options, owner)
      raise ArgumentError, "#{owner} expects a Hash of options, got #{options.inspect}" unless options.is_a?(Hash)

      options.each_with_object({}) do |(key, value), symbolized|
        unless key.is_a?(Symbol) || key.is_a?(String)
          raise ArgumentError, "#{owner} expects option names as Symbols or Strings, got #{key.inspect}"
        end
        raise ArgumentError, "#{owner} got `#{key}` both as a Symbol and as a String" if symbolized.key?(key.to_sym)

        symbolized[key.to_sym] = value
      end
    end

    # Copies hashes, arrays and strings, so freezing them leaves the caller's
    # own objects alone. A Proc is kept as it is, unfrozen.
    def deep_freeze(value)
      case value
      when Hash then value.to_h { |key, item| [key, deep_freeze(item)] }.freeze
      when Array then value.map { |item| deep_freeze(item) }.freeze
      when String then value.dup.freeze
      else value
      end
    end
  end
end
