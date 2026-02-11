# frozen_string_literal: true

# Service for sending sign-up form notifications as in-app messages.
#
# This service handles sign-up confirmation, queue notifications, and slot changes,
# sending them as in-app messages to users with accounts.
#
# Usage:
#   SignUpNotificationService.notify_confirmation(registration)
#   SignUpNotificationService.notify_queued(registration)
#   SignUpNotificationService.notify_slot_assigned(registration)
#   SignUpNotificationService.notify_slot_changed(registration)
#   SignUpNotificationService.notify_cancelled(registration)
#
class SignUpNotificationService
  class << self
    # Notify registrant of successful sign-up confirmation
    def notify_confirmation(registration)
      send_notification_for(
        registration: registration,
        template_key: "sign_up_confirmation"
      )
    end

    # Notify registrant they are on the waitlist/queue
    def notify_queued(registration)
      send_notification_for(
        registration: registration,
        template_key: "sign_up_queued"
      )
    end

    # Notify registrant a slot has been assigned
    def notify_slot_assigned(registration)
      send_notification_for(
        registration: registration,
        template_key: "sign_up_slot_assigned"
      )
    end

    # Notify registrant their slot has changed
    def notify_slot_changed(registration)
      send_notification_for(
        registration: registration,
        template_key: "sign_up_slot_changed"
      )
    end

    # Notify registrant their sign-up has been cancelled
    def notify_cancelled(registration)
      send_notification_for(
        registration: registration,
        template_key: "sign_up_cancelled"
      )
    end

    # Legacy method for backwards compatibility
    def send_notification(registration:, notification_type:)
      case notification_type.to_sym
      when :confirmation then notify_confirmation(registration)
      when :queued then notify_queued(registration)
      when :slot_assigned then notify_slot_assigned(registration)
      when :slot_changed then notify_slot_changed(registration)
      when :cancelled then notify_cancelled(registration)
      else { messages_sent: 0 }
      end
    end

    private

    def send_notification_for(registration:, template_key:)
      result = { messages_sent: 0 }

      # Get production and person context
      slot = registration.sign_up_slot
      instance = slot&.sign_up_form_instance || registration.sign_up_form_instance
      form = slot&.sign_up_form || instance&.sign_up_form
      production = form&.production
      person = registration.person

      # Only send messages to users with accounts
      return result unless person&.user.present?

      # Build template variables
      show = instance&.show
      show_name = show&.secondary_name.presence || show&.event_type&.titleize || form&.name || "TBD"
      show_date = show&.date_and_time&.strftime("%B %d, %Y at %l:%M %p") || "TBD"

      variables = {
        registrant_name: registration.display_name || "Guest",
        sign_up_form_name: form&.name || "Sign-Up",
        slot_name: slot&.display_name || "TBD",
        show_name: show_name,
        show_date: show_date,
        production_name: production&.name || ""
      }

      # Render the template
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

      # Send as in-app message (system_generated: true so it doesn't appear in sender's sent folder)
      message = MessageService.send_direct(
        sender: sender,
        recipient_person: person,
        subject: subject,
        body: body,
        production: production,
        organization: production&.organization,
        system_generated: true
      )
      result[:messages_sent] += 1 if message

      Rails.logger.info "[SignUpNotification] Sent #{template_key} message to #{person.name}"

      result
    end

    def find_sender(production)
      # Use the organization owner as the sender for notifications
      return nil unless production

      production.organization.owner
    end
  end
end
