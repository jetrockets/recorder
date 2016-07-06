class Recorder::RevisionDecorator < Draper::Decorator
  delegate_all

  decorates_association :item
  decorates_association :user

  # def author_name
  #   if source.user.present?
  #     self.user.display_name
  #   else
  #     'Somebody'
  #   end
  # end

  # def current_version
  #   return @current_version if defined?(@current_version)

  #   @current_version = if self.next.present?
  #     self.next.reify.decorate
  #   else
  #     self.item
  #   end
  # end

  # def previous_version
  #   @previous_version ||= self.reify(dup: true).decorate
  # end

  # def message
  #   # "Lorem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industry's standard dummy text ever since the 1500s. Over the years, sometimes by accident, sometimes on purpose (injected humour and the like)."
  #   # if source.event == 'create'
  #   #   source.object_changes.map do |key, changes|

  #   #   end
  #   # end
  # end

  def item_human_attribute_name(attribute)
    self.item.source.class.human_attribute_name(attribute)
  end

  # def ip_with_link
  #   if source.ip.present?
  #     h.link_to source.ip, "http://ipinfo.io/#{source.ip}", :target => '_blank'
  #   end
  # end
end
