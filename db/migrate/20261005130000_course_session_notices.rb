# frozen_string_literal: true

# Students hear about their sessions: each confirmed registration remembers
# what the student was told about every session (to know when one moved),
# which sessions they've been reminded of, and the theater picks how many
# days before a session the reminder goes.
class CourseSessionNotices < ActiveRecord::Migration[8.1]
  def up
    add_column :course_registrations, :told_sessions, :jsonb, null: false, default: {}
    add_column :course_registrations, :reminded_show_ids, :jsonb, null: false, default: []
    add_column :organizations, :course_reminder_days_before, :integer, default: 1

    # Everyone already registered was told what the sessions say today.
    say_with_time "remembering what current students were told" do
      CourseRegistration.reset_column_information
      CourseRegistration.where(status: "confirmed").includes(course_offering: { production: :shows }).find_each do |registration|
        registration.update_columns(told_sessions: CourseSessionChange.snapshot(registration.course_offering))
      end
    end
  end

  def down
    remove_column :organizations, :course_reminder_days_before
    remove_column :course_registrations, :reminded_show_ids
    remove_column :course_registrations, :told_sessions
  end
end
