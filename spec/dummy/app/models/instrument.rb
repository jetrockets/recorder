# frozen_string_literal: true

# Declares per-model `recorder` options. Shares the `securities` table.
class Instrument < ApplicationRecord
  include ::Recorder::Observer

  self.table_name = 'securities'

  belongs_to :guard, class_name: 'Instrument', optional: true

  recorder ignore: %i[identifier updated_at],
    associations: {guard: {only: %i[name]}},
    changes: :ticker_change

  def ticker_change(event)
    {ticker: [nil, identifier]} if event == :create
  end
end
