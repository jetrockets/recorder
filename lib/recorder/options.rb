# frozen_string_literal: true

require 'active_support/core_ext/hash/keys'

module Recorder
  # Checks the options passed to `.recorder` and stores them as a frozen,
  # symbol-keyed copy.
  # @api private
  module Options
    KEYS = %i[ignore only associations changes].freeze
    ASSOCIATION_KEYS = %i[ignore only].freeze
    # Asynchronous recording was removed in 2.0.0.
    REMOVED_KEYS = %i[async delay].freeze

    module_function

    # @raise [ArgumentError] for options that are not a Hash, an unknown key,
    #   or an option `Recorder::Tape::Data` cannot apply
    def normalize(options)
      options = symbolize(options, '`recorder`')
      removed = options.keys & REMOVED_KEYS
      if removed.any?
        raise ArgumentError, "`recorder` does not take #{removed.map { |key| "`#{key}:`" }.join(" or ")}: " \
          'asynchronous recording was removed in 2.0.0, and every revision is written in the save transaction.'
      end

      options.assert_valid_keys(*KEYS)
      Recorder::Tape::Data.validate_changes_option!(options[:changes])
      options[:associations] = normalize_associations(options[:associations]) if options.key?(:associations)

      deep_freeze(options)
    end

    # Takes a Hash of association name => options, or an Array of names.
    def normalize_associations(associations)
      return associations if associations.nil? || associations.is_a?(Array)
      unless associations.is_a?(Hash)
        raise ArgumentError, "`associations:` expects a Hash or an Array of names, got #{associations.inspect}"
      end

      associations.to_h do |name, options|
        next [name, nil] if options.nil?

        options = symbolize(options, "The options for association #{name.inspect}")
        options.assert_valid_keys(*ASSOCIATION_KEYS)

        [name, options]
      end
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
    # own objects alone.
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
