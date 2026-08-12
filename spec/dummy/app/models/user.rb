# frozen_string_literal: true

# Spec fixture only. Recorder::Revision `belongs_to :user`, so something has to
# answer to that constant; the gem expects host apps to provide their own.
class User < ApplicationRecord
end
