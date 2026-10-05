# frozen_string_literal: true

# Tim, 2026-10-05: course reminders default to two days before a session
# (like tickets), and producers choose their own daily sales note, so the
# theater-level switch (never shown anywhere) goes.
class DecisionsAfterTheReview < ActiveRecord::Migration[8.1]
  def up
    change_column_default :organizations, :course_reminder_days_before, from: 1, to: 2
    execute "UPDATE organizations SET course_reminder_days_before = 2 WHERE course_reminder_days_before = 1"
    remove_column :ticketing_profiles, :producer_daily_emails
  end

  def down
    add_column :ticketing_profiles, :producer_daily_emails, :boolean, default: true, null: false
    change_column_default :organizations, :course_reminder_days_before, from: 2, to: 1
  end
end
