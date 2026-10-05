# frozen_string_literal: true

# Reminders before a class session (Courses → Settings → Reminders). Every
# morning, students whose session is the theater's chosen number of days
# away get the time and the place again. Each registration is reminded once
# per session, stamped before its email is queued, so a rerun never sends
# twice.
class CourseRemindersJob < ApplicationJob
  queue_as :default

  def perform(today = Date.current)
    Organization.where.not(course_reminder_days_before: nil).find_each do |organization|
      day = today + organization.course_reminder_days_before
      sessions = Show.joins(:production).where(productions: { organization_id: organization.id })
                     .where.not(course_offering_id: nil).where(canceled: false, date_and_time: day.all_day)
      sessions.find_each do |show|
        CourseRegistration.confirmed.where(course_offering_id: show.course_offering_id).includes(:person).find_each do |registration|
          next if registration.reminded_show_ids.include?(show.id)

          registration.update_columns(reminded_show_ids: registration.reminded_show_ids + [ show.id ])
          CourseRegistrationMailer.reminder(registration, show).deliver_later
        end
      end
    rescue StandardError => e
      Rails.logger.error("[CourseRemindersJob] org #{organization.id}: #{e.class}: #{e.message}")
    end
  end
end
