# frozen_string_literal: true

class AddCastingEnabledToShows < ActiveRecord::Migration[8.1]
  def change
    add_column :shows, :casting_enabled, :boolean, default: true, null: false

    # Set existing records based on event_type
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE shows
          SET casting_enabled = CASE
            WHEN event_type = 'show' THEN true
            ELSE false
          END
        SQL
      end
    end
  end
end
