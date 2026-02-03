# frozen_string_literal: true

# Service for sending sign-up form notifications as in-app messages.
#
# This service handles sign-up confirmation, queue notifications, and slot changes,
# sending them as in-app messages to users with accounts.
#
# Usage:
#   SignUpNotificationService.send_notification(
#     registration: registration,
#     notification_type: :confirmation
#   )
#
class SignUpNotificationService
  NOTIFICATION_TYPES = %i[confirmation queued slot_assigned slot_changed cancelled].freeze

  TEMPLATE_KEYS = {
    confirmation: "sign_up_confirmation",
    queued: "sign_up_queued",
    slot_assigned: "sign_up_slot_assigned",
    slot_changed: "sign_up_slot_changed",
    cancelled: "sign_up_cancelled"
  }.freeze

  class << self
    # Send a sign-up notification as an in-app message
    #
    # @param registration [SignUpRegistration] The registration
    # @param notification_type [Symbol] One of :confirmation, :queued, :slot_assigned, :slot_changed, :cancelled
    # @return [Hash] { messages_sent: Integer }
    def send_notification(registration:, notification_type:)
      result = { messages_sent: 0 }

      # Validate notification type
      return result unless NOTIFICATION_TYPES.include?(notification_type.to_sym)

      # Get production and person context
      slot = registration.sign_up_slot
      instance = slot&.sign_up_form_instance || registration.sign_up_form_instance
      form = slot&.sign_up_form || instance&.sign_up_form
      production = form&.production
      person = registration.person

      # Only send messages to users with accounts
      return result unless person&.user.present?

      # Get template key
      template_key = TEMPLATE_KEYS[notification_type.to_sym]

      # Render the template
      variables = build_template_variables(registration, slot, instance, form, production)

      begin
        template = ContentTemplateService.render(template_key, variables)
      rescue StandardError => e
        Rails.logger.error "SignUpNotificationService: Failed to render template #{template_key}: #{e.message}"
        return result
      end

      subject = template[:subject]
      body = template[:body]

      # Find a sender for the message
      sender = find_sender(production)
      return result unless sender.present?

      # Send as in-app message
      message = MessageService.send_direct(
        sender: sender,
        recipient_person: person,
        subject: subject,
        body: body,
        production: production,
        organization: production&.organization
      )
      result[:messages_sent] += 1 if message

      Rails.logger.info "[SignUpNotification] Sent #{notification_type} message to #{person.name}"

      result
    end

    private

    def build_template_variables(registration, slot, instance, form, production)
      show = instance&.show
      show_name = show&.secondary_name.presence || show&.event_type&.titleize || instance&.show_name || "TBD"
      show_date = show&.date_and_time&.strftime("%B %d, %Y at %l:%M %p") || instance&.show_date&.strftime("%B %d, %Y") || "TBD"

      {
        registrant_name: registration.display_name || "Guest",
        sign_up_form_name: form&.name || "Sign-Up",
        slot_name: slot&.display_name || "TBD",
        show_name: show_name,
        show_date: show_date,
        production_name: production&.name || ""
      }
    end

    def find_sender(production)
      # Use the production's primary team member or organization owner as sender
      return nil unless production

      # Try to find the production's primary team member
      primary_role = production.organization_roles.find_by(primary: true)
      return primary_role.user if primary_role&.user.present?

      # Fall back to organization owner
      production.organization.owner
    end
  end
end
