# frozen_string_literal: true

class AddTicketingExclusions < ActiveRecord::Migration[8.0]
  def change
    # Production-level ticketing settings
    add_column :productions, :ticketing_enabled, :boolean, default: true, null: false
    add_column :productions, :ticketing_exclusion_reason, :string

    # Show-level ticketing override
    add_column :shows, :ticketing_enabled, :boolean
    add_column :shows, :ticketing_exclusion_reason, :string

    # Note: shows.ticketing_enabled is nullable - nil means "inherit from production"
    # true = explicitly enabled even if production disabled
    # false = explicitly disabled even if production enabled
  end
end
