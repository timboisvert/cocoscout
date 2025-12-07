# frozen_string_literal: true

class AddEventTypeToShows < ActiveRecord::Migration[8.0]
  def change
    add_column :shows, :event_type, :string, default: 'show', null: false
  end
end
