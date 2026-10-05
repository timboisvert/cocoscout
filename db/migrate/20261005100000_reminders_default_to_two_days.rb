# frozen_string_literal: true

# Buyers' reminder goes out two days before the show unless the theater
# chooses otherwise (it was one). Every choice stays available.
class RemindersDefaultToTwoDays < ActiveRecord::Migration[8.1]
  def up
    change_column_default :ticketing_profiles, :reminder_days_before, from: 1, to: 2
    execute "UPDATE ticketing_profiles SET reminder_days_before = 2 WHERE reminder_days_before = 1"
  end

  def down
    change_column_default :ticketing_profiles, :reminder_days_before, from: 2, to: 1
  end
end
