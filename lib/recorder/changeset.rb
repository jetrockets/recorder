module Recorder
  class Changeset
    attr_reader :item, :changes

    def initialize(item, changes)
      @item = item;
      @changes = Hash[changes]
    end

    def keys
      self.changes.try(:keys) || []
    end

    def human_attribute_name(attribute)
      if defined?(Draper) && self.item.decorated?
        self.item.source.class.human_attribute_name(attribute.to_s)
      else
        self.item.class.human_attribute_name(attribute.to_s)
      end
    end

    def previous(attribute)
      self.try("previous_#{attribute}") || self.previous_version.try(attribute)
    end

    def previous_version
      return @previous_version if defined?(@previous_version)

      @previous_version = self.item.dup

      self.changes.each do |key, change|
        @previous_version.send("#{key}=", change[0])
      end

      @previous_version
    end

    def next(attribute)
      self.try("next_#{attribute}") || self.next_version.try(attribute)
    end

    def next_version
      return @next_version if defined?(@next_version)

      @next_version = self.item.dup

      self.changes.each do |key, change|
        @next_version.send("#{key}=", change[1])
      end

      @next_version
    end
  end
end
