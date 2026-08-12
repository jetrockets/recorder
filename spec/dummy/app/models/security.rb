# frozen_string_literal: true

class Security < ApplicationRecord
  include ::Recorder::Observer

  self.inheritance_column = nil

  # Including Observer alone only adds the `revisions` association -- it is this
  # call that registers the after_create/update/destroy callbacks. Without it
  # nothing is ever recorded, so the end-to-end specs need it.
  recorder
end
