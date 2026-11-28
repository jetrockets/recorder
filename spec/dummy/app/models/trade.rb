# frozen_string_literal: true

# Has a UUID primary key and an inheritance column.
class Trade < ApplicationRecord
  include ::Recorder::Observer

  recorder
end
