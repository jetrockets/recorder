# frozen_string_literal: true

# An abstract parent that declares `recorder` for subclasses with tables of
# their own, outside STI.
class Listing < ApplicationRecord
  include ::Recorder::Observer

  self.abstract_class = true

  recorder associations: {issuer: {only: %i[name]}}
end
