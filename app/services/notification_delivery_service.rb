# frozen_string_literal: true

# Unified notification service that handles delivery via messages and/or email
# based on ContentTemplate channel settings.
#
# This service replaces individual notification services by providing a single
# entry point for all notifications that respects the channel setting.
#
# Usage:
#   NotificationDeliveryService.deliver(
#     template_key: "vacancy_invitation",
#     variables: { recipient_name: "John", ... },
#     sender: current_user,
#     recipient: person,         # Person who receives the notification
#     production: production,    # Optional, for context
#     email_batch_id: batch.id   # Optional, for tracking
#   )
#
class NotificationDeliveryService
  class << self
    # Deliver a notification via the appropriate channel(s)
    #
    # @param template_key [String] The ContentTemplate key
    # @param variables [Hash] Variables to interpolate in the template
    # @param sender [User] The user sending the notification (for messages)
    # @param recipient [Person] The person receiving the notification
    # @param production [Production, nil] Optional production context
    # @param organization [Organization, nil] Optional organization context
    # @param email_batch_id [Integer, nil] Optional email batch ID for tracking
    # @param system_generated [Boolean] Whether this is an automated transactional message
    # @return [Hash] { message: Message, email_sent: Boolean }
    def deliver(template_key:, variables:, sender:, recipient:, production: nil, organization: nil, email_batch_id: nil, system_generated: false)
      result = { message: nil, email_sent: false }

      # Get the channel from the template
      channel = ContentTemplateService.channel_for(template_key)

      # Render the template
      rendered = ContentTemplateService.render(template_key, variables)
      subject = rendered[:subject]
      body = rendered[:body]

      # Send message if channel is :message or :both
      if channel.in?([ :message, :both ]) && sender && recipient.user.present?
        result[:message] = MessageService.send_direct(
          sender: sender,
          recipient_person: recipient,
          subject: subject,
          body: body,
          production: production,
          organization: organization || production&.organization,
          system_generated: system_generated
        )
      end

      # Send email if channel is :email or :both
      if channel.in?([ :email, :both ]) && recipient.email.present?
        AppMailer.with(
          template_key: template_key,
          to: recipient.email,
          variables: variables,
          email_batch_id: email_batch_id
        ).send_template.deliver_later

        result[:email_sent] = true
      end

      result
    end

    # Deliver to multiple recipients
    #
    # @param template_key [String] The ContentTemplate key
    # @param variables_proc [Proc] A proc that takes a recipient and returns variables hash
    # @param sender [User] The user sending the notification
    # @param recipients [Array<Person>] The people receiving the notification
    # @param production [Production, nil] Optional production context
    # @param organization [Organization, nil] Optional organization context
    # @param system_generated [Boolean] Whether this is an automated transactional message
    # @return [Hash] { messages_sent: Integer, emails_sent: Integer }
    def deliver_to_many(template_key:, variables_proc:, sender:, recipients:, production: nil, organization: nil, system_generated: false)
      results = { messages_sent: 0, emails_sent: 0 }

      # Create email batch if sending to multiple recipients
      email_batch = nil
      channel = ContentTemplateService.channel_for(template_key)

      if channel.in?([ :email, :both ]) && recipients.size > 1 && sender
        rendered = ContentTemplateService.render(template_key, variables_proc.call(recipients.first))
        email_batch = EmailBatch.create!(
          user: sender,
          subject: rendered[:subject],
          recipient_count: recipients.size,
          sent_at: Time.current
        )
      end

      recipients.each do |recipient|
        variables = variables_proc.call(recipient)

        result = deliver(
          template_key: template_key,
          variables: variables,
          sender: sender,
          recipient: recipient,
          production: production,
          organization: organization,
          email_batch_id: email_batch&.id,
          system_generated: system_generated
        )

        results[:messages_sent] += 1 if result[:message]
        results[:emails_sent] += 1 if result[:email_sent]
      end

      results
    end

    # Deliver to production team members with notifications enabled
    #
    # @param template_key [String] The ContentTemplate key
    # @param variables [Hash] Variables to interpolate in the template
    # @param production [Production] The production
    # @param sender [User, nil] Optional sender (defaults to org owner)
    # @return [Hash] { messages_sent: Integer, emails_sent: Integer }
    def deliver_to_team(template_key:, variables:, production:, sender: nil)
      # Leave sender as nil for system messages — production name shows instead of a person

      recipients = find_notifiable_team_members(production)
      return { messages_sent: 0, emails_sent: 0 } if recipients.empty?

      results = { messages_sent: 0, emails_sent: 0 }
      channel = ContentTemplateService.channel_for(template_key)

      # Create email batch if needed
      email_batch = nil
      if channel.in?([ :email, :both ]) && recipients.size > 1 && sender
        rendered = ContentTemplateService.render(template_key, variables)
        email_batch = EmailBatch.create!(
          user: sender,
          subject: rendered[:subject],
          recipient_count: recipients.size,
          sent_at: Time.current
        )
      end

      # Render once (same content for all team members)
      rendered = ContentTemplateService.render(template_key, variables)
      subject = rendered[:subject]
      body = rendered[:body]

      recipients.each do |user|
        person = user.person

        # Send message if channel is :message or :both
        if channel.in?([ :message, :both ]) && person
          message = MessageService.send_direct(
            sender: sender,
            recipient_person: person,
            subject: subject,
            body: body,
            production: production,
            organization: production.organization,
            system_generated: true
          )
          results[:messages_sent] += 1 if message
        end

        # Send email if channel is :email or :both
        if channel.in?([ :email, :both ]) && user.email_address.present?
          AppMailer.with(
            template_key: template_key,
            to: user.email_address,
            variables: variables,
            email_batch_id: email_batch&.id
          ).send_template.deliver_later

          results[:emails_sent] += 1
        end
      end

      results
    end

    private

    def find_notifiable_team_members(production)
      ProductionNotificationSetting.ensure_settings_for(production)
      ProductionNotificationSetting.where(production: production, enabled: true)
                                   .includes(:user)
                                   .map(&:user)
                                   .compact
    end
  end
end
