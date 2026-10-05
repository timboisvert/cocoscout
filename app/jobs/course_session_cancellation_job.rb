# frozen_string_literal: true

# Emails each student registered for canceled sessions, in the manager's
# words (CourseSessionCancellation): one email per student naming the dates.
class CourseSessionCancellationJob < ApplicationJob
  queue_as :default

  def perform(show_ids, subject, body)
    shows = Show.where(id: show_ids).includes(:location).order(:date_and_time).to_a
    shows.group_by(&:course_offering_id).each do |offering_id, canceled|
      next unless offering_id

      CourseRegistration.confirmed.where(course_offering_id: offering_id).includes(:person).find_each do |registration|
        CourseRegistrationMailer.session_canceled(registration, canceled, subject: subject, body: body).deliver_now
      end
    end
  end
end
