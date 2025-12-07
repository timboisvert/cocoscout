# frozen_string_literal: true

class AddRecurrenceGroupIdToShows < ActiveRecord::Migration[8.0]
  def change
    add_column :shows, :recurrence_group_id, :string
  end
end
