class Recorder::Changeset
  attr_reader :item, :changes

  def initialize(item, changes)
    @item = item; @changes = changes
  end

  def attributes
    self.changes.keys
  end

  def human_attribute_name(attribute)
    self.item.class.human_attribute_name(attribute.to_s)
  end

  def before(attribute)
    self.changes[attribute.to_s][0]
  end

  def after(attribute)
    self.changes[attribute.to_s][1]
  end

  # def

  # def item_human_attribute_name(attribute)
  #   self.item.source.class.human_attribute_name(attribute)
  # end
end
