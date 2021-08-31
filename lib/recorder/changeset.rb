module Recorder
  class Changeset
    attr_reader :item, :changes

    def initialize(item, changes)
      @item = item;
      @changes = Hash[changes]
    end

    def keys
      changes.try(:keys) || []
    end

    def human_attribute_name(attribute)
      if defined?(Draper) && item.decorated?
        item.source.class.human_attribute_name(attribute.to_s)
      else
        item.class.human_attribute_name(attribute.to_s)
      end
    end

    def previous(attribute)
      try("previous_#{attribute}") || previous_version.try(attribute)
    end

    def previous_version
      return @previous_version if defined?(@previous_version)

      @previous_version = item.dup

      changes.each do |key, change|
        @previous_version.send("#{key}=", change[0])
      end

      @previous_version
    end

    def next(attribute)
      try("next_#{attribute}") || next_version.try(attribute)
    end

    def next_version
      return @next_version if defined?(@next_version)

      @next_version = item.dup

      changes.each do |key, change|
        @next_version.send("#{key}=", change[1])
      end

      @next_version
    end
  end
end
