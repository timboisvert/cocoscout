# frozen_string_literal: true

# Tells each student of a moved session, in the manager's words (see
# CourseSessionChange). Each registration is marked told as its emails go,
# so a rerun only reaches whoever is left.
class CourseSessionChangeJob < ApplicationJob
  queue_as :default

  def perform(offering_id, subject, body)
    offering = CourseOffering.find_by(id: offering_id)
    return unless offering

    CourseSessionChange.registrations(offering).each do |registration|
      CourseSessionChange.moved(registration).each do |moved|
        CourseRegistrationMailer.session_changed(registration, moved, subject: subject, body: body).deliver_now
      end
      CourseSessionChange.mark_told!(offering, [ registration ])
    end
  end
end
