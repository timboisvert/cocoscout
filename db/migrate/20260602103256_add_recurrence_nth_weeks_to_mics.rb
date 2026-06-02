# frozen_string_literal: true

# Some mics recur on multiple specific weeks per month — e.g.
# "first and third Monday of every month." The existing
# `recurrence_nth_week` integer only supports a single week. Add
# `recurrence_nth_weeks` as a JSON-array column to capture the set,
# used when `recurrence_pattern = monthly_nth_weekdays` (plural).
class AddRecurrenceNthWeeksToMics < ActiveRecord::Migration[8.1]
  def change
    add_column :mics, :recurrence_nth_weeks, :jsonb, default: [], null: false
  end
end
