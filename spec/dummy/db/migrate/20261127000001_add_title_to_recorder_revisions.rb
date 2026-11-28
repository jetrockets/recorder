# frozen_string_literal: true

# Spec fixture: a column an app added to `recorder_revisions`, which
# `Recorder.record` sets as a keyword.
class AddTitleToRecorderRevisions < ActiveRecord::Migration[6.1]
  def change
    add_column :recorder_revisions, :title, :string
  end
end
