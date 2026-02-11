# frozen_string_literal: true

# Service for sending show-related notifications as both messages and emails.
#
# This service handles show cancellation and other show-related notifications,
# routing them through the message system or email based on template channel settings.
#
# Usage:
#   ShowNotificationService.send_cancellation_notification(
#     person: person,
#     show: show,
#     production: production,
#     sender: current_user,
#     body: email_body,        # Optional - uses template if not provided
#     subject: email_subject,  # Optional - uses template if not provided
#     email_batch_id: batch.id
#   )
#
class ShowNotificationService
  TEMPLATE_KEY = "show_canceled"

  class << self
    # Send show cancellation notification
    #
    # @param person [Person] The person to notify
    # @param show [Show] The cancelled show
    # @param production [Production] The production
    # @param sender [User] The user sending the notification
    # @param body [String, nil] Optional notification body (HTML) - uses template if nil
    # @param subject [String, nil] Optional notification subject - uses template if nil
    # @param email_batch_id [Integer] Optional batch ID for tracking
    # @return [Hash] { messages_sent: Integer, emails_sent: Integer }
    def send_cancellation_notification(person:, show:, production:, sender:, body: nil, subject: nil, email_batch_id: nil)
      result = { messages_sent: 0, emails_sent: 0 }

      return result unless person&.email.present?

      # Check template channel to determine delivery method
      channel = ContentTemplateService.channel_for(TEMPLATE_KEY) || :both

      # Render template if custom body/subject not provided
      if body.blank? || subject.blank?
        rendered = ContentTemplateService.render(TEMPLATE_KEY, {
          recipient_name: person.first_name || person.name,
          production_name: production.name,
          event_type: show.event_type&.titleize || "Event",
          event_date: show.date_and_time&.strftime("%A, %B %-d, %Y") || "TBD",
          show_name: show.secondary_name.presence || show.event_type&.titleize || "Event",
          location: show.location&.name
        })
        subject = subject.presence || rendered[:subject]
        body = body.presence || rendered[:body]
      end

      # Send as in-app message (system_generated: true so it doesn't appear in sender's sent folder)
      if channel == :message || channel == :both
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
      end

      # Send as email (for :email or :both channels, or if user has no account)
      if channel == :email || channel == :both || person.user.nil?
        # Check user notification preferences
        should_email = person.user.nil? || person.user.notification_enabled?(:show_cancellations)

        if should_email
          begin
            Manage::ShowMailer.canceled_notification(
              person: person,
              show: show,
              production: production,
              email_subject: subject,
              email_body: body,
              email_batch_id: email_batch_id
            ).deliver_later
            result[:emails_sent] += 1
          rescue StandardError => e
            Rails.logger.error "ShowNotificationService: Failed to send email to #{person.email}: #{e.message}"
          end
        end
      end

      result
    end
  end
end
