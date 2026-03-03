# frozen_string_literal: true

# Service for sending course registration notifications:
# 1. To the registrant: confirmation email + in-app message (channel: "both")
# 2. To the production team: in-app message only (channel: "message")
#
# Usage:
#   CourseRegistrationNotificationService.notify_registrant(registration)
#   CourseRegistrationNotificationService.notify_team(registration)
#
class CourseRegistrationNotificationService
  REGISTRANT_TEMPLATE_KEY = "course_registration_confirmed"
  PRODUCER_TEMPLATE_KEY = "course_registration_producer_notification"

  class << self
    # Notify the registrant that their registration is confirmed
    def notify_registrant(registration)
      person = registration.person
      return unless person&.user.present?

      offering = registration.course_offering
      production = offering.production
      sender = find_sender(production)
      return unless sender

      variables = build_registrant_variables(registration, offering, production, person)

      NotificationDeliveryService.deliver(
        template_key: REGISTRANT_TEMPLATE_KEY,
        variables: variables,
        sender: sender,
        recipient: person,
        production: production,
        organization: production.organization,
        system_generated: true
      )
    end

    # Notify the production team about a new registration (in-app only)
    def notify_team(registration)
      offering = registration.course_offering
      production = offering.production

      variables = build_producer_variables(registration, offering, production)

      NotificationDeliveryService.deliver_to_team(
        template_key: PRODUCER_TEMPLATE_KEY,
        variables: variables,
        production: production
      )
    end

    private

    def build_registrant_variables(registration, offering, production, person)
      sessions = offering.sessions
      session_lines = sessions.map do |show|
        show.date_and_time.strftime("%A, %B %-d, %Y at %-I:%M %p")
      end

      {
        recipient_name: person.first_name || person.name&.split&.first || "there",
        course_title: offering.title,
        amount_paid: registration.formatted_amount,
        instructor_name: offering.instructor_name.presence,
        class_schedule: session_lines.any? ? session_lines.join("\n") : nil,
        dashboard_url: Rails.application.routes.url_helpers.root_url(**default_url_options)
      }
    end

    def build_producer_variables(registration, offering, production)
      registrant = registration.person

      {
        registrant_name: registrant&.name || "Someone",
        course_title: offering.title,
        amount_paid: registration.formatted_amount,
        total_registrations: offering.confirmed_registrations_count.to_s,
        spots_remaining: offering.spots_remaining&.to_s,
        course_offering_url: Rails.application.routes.url_helpers.manage_course_offering_url(
          offering,
          **default_url_options
        )
      }
    end

    def find_sender(production)
      production.organization.owner ||
        production.production_permissions.includes(:user).find_by(role: "manager")&.user
    end

    def default_url_options
      Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
    end
  end
end
