# frozen_string_literal: true

# Adds a custom_dates jsonb column for mics that don't fit any
# recurring schedule — pop-ups, one-off mini-runs, residency series.
# Used when `recurrence_pattern` is `custom_dates` (enum value 5).
class AddCustomDatesToMics < ActiveRecord::Migration[8.1]
  def change
    add_column :mics, :custom_dates, :jsonb, default: [], null: false
  end
end
