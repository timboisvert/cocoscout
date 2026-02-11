# frozen_string_literal: true

# Service for sending casting notifications as both messages and emails.
#
# This service handles the transition from email-only to message-first notifications
# for casting changes. It creates in-app messages as the primary communication channel
# while optionally sending email notifications based on template channel settings.
#
# Usage:
#   # Send cast notification to a person
#   CastingNotificationService.send_cast_notification(
#     person: person,
#     show: show,
#     production: production,
#     sender: current_user,
#     body: personalized_body,
#     subject: email_subject,
#     email_batch_id: batch.id
#   )
#
#   # Send removed from cast notification
#   CastingNotificationService.send_removed_notification(
#     person: person,
#     show: show,
#     production: production,
#     sender: current_user,
#     body: personalized_body,
#     subject: email_subject,
#     email_batch_id: batch.id
#   )
#
class CastingNotificationService
  class << self
    # Send "added to cast" notification
    #
    # @param person [Person] The person being cast
    # @param show [Show] The show they're cast in
    # @param production [Production] The production
    # @param sender [User] The user sending the notification
    # @param body [String] The notification body (HTML)
    # @param subject [String] The notification subject
    # @param email_batch_id [Integer] Optional batch ID for tracking
    # @return [Hash] { messages_sent: Integer, emails_sent: Integer }
    def send_cast_notification(person:, show:, production:, sender:, body:, subject:, email_batch_id: nil)
      send_notification(
        template_key: "cast_notification",
        person: person,
        show: show,
        production: production,
        sender: sender,
        body: body,
        subject: subject,
        email_batch_id: email_batch_id,
        mailer_method: :cast_notification
      )
    end

    # Send "removed from cast" notification
    #
    # @param person [Person] The person being removed
    # @param show [Show] The show they're removed from
    # @param production [Production] The production
    # @param sender [User] The user sending the notification
    # @param body [String] The notification body (HTML)
    # @param subject [String] The notification subject
    # @param email_batch_id [Integer] Optional batch ID for tracking
    # @return [Hash] { messages_sent: Integer, emails_sent: Integer }
    def send_removed_notification(person:, show:, production:, sender:, body:, subject:, email_batch_id: nil)
      send_notification(
        template_key: "removed_from_cast_notification",
        person: person,
        show: show,
        production: production,
        sender: sender,
        body: body,
        subject: subject,
        email_batch_id: email_batch_id,
        mailer_method: :removed_notification
      )
    end

    private

    # Casting notifications are message-only (no email)
    # system_generated: true so it doesn't appear in sender's sent folder
    def send_notification(template_key:, person:, show:, production:, sender:, body:, subject:, email_batch_id:, mailer_method:)
      result = { messages_sent: 0, emails_sent: 0 }

      return result unless person&.email.present?

      # Only send to users with accounts (message-only)
      if person.user.present?
        message = MessageService.send_direct(
          sender: sender,
          recipient_person: person,
          subject: subject,
          body: body,
          production: production,
          organization: production.organization,
          system_generated: true
        )
        result[:messages_sent] += 1 if message
      end

      result
    end
  end
end
