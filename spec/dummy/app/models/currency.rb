# frozen_string_literal: true

# Has a string primary key, the currency's code.
class Currency < ApplicationRecord
  include ::Recorder::Observer

  recorder
end
