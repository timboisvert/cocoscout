# frozen_string_literal: true

# Service for sending audition cycle notifications as both messages and emails.
#
# This service handles the transition from email-only to message-first notifications
# for audition cycles. It creates in-app messages as the primary communication channel
# while optionally sending email notifications as a fallback/digest.
#
# Usage:
#   # Send casting results (added to cast / not cast)
#   AuditionNotificationService.send_casting_results(
#     production: production,
#     audition_cycle: cycle,
#     sender: current_user,
#     cast_assignments: [...],  # People being added to casts
#     rejections: [...],        # People not being added
#     email_batch: batch
#   )
#
#   # Send audition invitations (invited / not invited)
#   AuditionNotificationService.send_audition_invitations(
#     production: production,
#     audition_cycle: cycle,
#     sender: current_user,
#     invitations: [...],    # People scheduled for auditions
#     not_invited: [...],    # People not scheduled
#     email_batch: batch
#   )
#
class AuditionNotificationService
  class << self
    # Send casting results to auditionees
    #
    # @param production [Production] The production
    # @param audition_cycle [AuditionCycle] The audition cycle
    # @param sender [User] The user sending notifications
    # @param cast_assignments [Array<Hash>] People added to casts: { person:, talent_pool:, body: }
    # @param rejections [Array<Hash>] People not added: { person:, body: }
    # @param email_batch [EmailBatch] Optional batch for email tracking
    # @return [Hash] { messages_sent: Integer, emails_sent: Integer }
    def send_casting_results(production:, audition_cycle:, sender:,
                             cast_assignments: [], rejections: [], email_batch: nil)
      results = { messages_sent: 0, emails_sent: 0 }

      # Process cast assignments (people being added to a talent pool/cast)
      cast_assignments.each do |assignment|
        result = send_cast_notification(
          production: production,
          audition_cycle: audition_cycle,
          sender: sender,
          person: assignment[:person],
          talent_pool: assignment[:talent_pool],
          custom_body: assignment[:body],
          custom_subject: assignment[:subject],
          email_batch: email_batch
        )
        results[:messages_sent] += result[:messages_sent]
        results[:emails_sent] += result[:emails_sent]
      end

      # Process rejections (people not being added)
      rejections.each do |rejection|
        result = send_rejection_notification(
          production: production,
          audition_cycle: audition_cycle,
          sender: sender,
          person: rejection[:person],
          custom_body: rejection[:body],
          custom_subject: rejection[:subject],
          email_batch: email_batch
        )
        results[:messages_sent] += result[:messages_sent]
        results[:emails_sent] += result[:emails_sent]
      end

      results
    end

    # Send audition invitation results
    #
    # @param production [Production] The production
    # @param audition_cycle [AuditionCycle] The audition cycle
    # @param sender [User] The user sending notifications
    # @param invitations [Array<Hash>] People invited: { person:, audition_sessions:, body: }
    # @param not_invited [Array<Hash>] People not invited: { person:, body: }
    # @param email_batch [EmailBatch] Optional batch for email tracking
    # @return [Hash] { messages_sent: Integer, emails_sent: Integer }
    def send_audition_invitations(production:, audition_cycle:, sender:,
                                  invitations: [], not_invited: [], email_batch: nil)
      results = { messages_sent: 0, emails_sent: 0 }

      # Process invitations
      invitations.each do |invitation|
        result = send_invitation_notification(
          production: production,
          audition_cycle: audition_cycle,
          sender: sender,
          person: invitation[:person],
          custom_body: invitation[:body],
          email_batch: email_batch
        )
        results[:messages_sent] += result[:messages_sent]
        results[:emails_sent] += result[:emails_sent]
      end

      # Process not invited
      not_invited.each do |rejection|
        result = send_not_invited_notification(
          production: production,
          audition_cycle: audition_cycle,
          sender: sender,
          person: rejection[:person],
          custom_body: rejection[:body],
          email_batch: email_batch
        )
        results[:messages_sent] += result[:messages_sent]
        results[:emails_sent] += result[:emails_sent]
      end

      results
    end

    private

    # Send "added to cast" notification
    def send_cast_notification(production:, audition_cycle:, sender:,
                               person:, talent_pool:, custom_body:, custom_subject: nil, email_batch:)
      template_key = "audition_added_to_cast"
      subject = custom_subject.presence || "[#{production.name}] Welcome to the cast!"

      body = custom_body.presence || default_cast_body(person, production, talent_pool)

      send_notification(
        template_key: template_key,
        subject: subject,
        body: body,
        production: production,
        sender: sender,
        person: person,
        message_type: :talent_pool,
        visibility: :production,
        email_batch: email_batch
      )
    end

    # Send "not being added" notification
    def send_rejection_notification(production:, audition_cycle:, sender:,
                                    person:, custom_body:, custom_subject: nil, email_batch:)
      template_key = "audition_not_cast"
      subject = custom_subject.presence || "[#{production.name}] Audition Results"

      body = custom_body.presence || default_rejection_body(person, production)

      send_notification(
        template_key: template_key,
        subject: subject,
        body: body,
        production: production,
        sender: sender,
        person: person,
        message_type: :talent_pool,
        visibility: :personal, # Rejection is private
        email_batch: email_batch
      )
    end

    # Send "invited to audition" notification
    def send_invitation_notification(production:, audition_cycle:, sender:,
                                     person:, custom_body:, custom_subject: nil, email_batch:)
      template_key = "audition_invitation"
      subject = custom_subject.presence || "#{production.name} Auditions"

      body = custom_body.presence || default_invitation_body(person, production, audition_cycle)

      send_notification(
        template_key: template_key,
        subject: subject,
        body: body,
        production: production,
        sender: sender,
        person: person,
        message_type: :talent_pool,
        visibility: :production,
        email_batch: email_batch,
        mailer_method: :invitation_notification
      )
    end

    # Send "not invited to audition" notification
    def send_not_invited_notification(production:, audition_cycle:, sender:,
                                      person:, custom_body:, custom_subject: nil, email_batch:)
      template_key = "audition_not_invited"
      subject = custom_subject.presence || "[#{production.name}] Audition Results"

      body = custom_body.presence || default_not_invited_body(person, production)

      send_notification(
        template_key: template_key,
        subject: subject,
        body: body,
        production: production,
        sender: sender,
        person: person,
        message_type: :talent_pool,
        visibility: :personal, # Not invited is private
        email_batch: email_batch,
        mailer_method: :invitation_notification
      )
    end

    # Core notification delivery
    # @param mailer_method [Symbol] :casting_notification or :invitation_notification
    def send_notification(template_key:, subject:, body:, production:, sender:,
                          person:, message_type:, visibility:, email_batch:,
                          mailer_method: :casting_notification)
      result = { messages_sent: 0, emails_sent: 0 }

      return result unless person&.email.present?

      # Check template channel to determine delivery method
      channel = ContentTemplateService.channel_for(template_key) || :message

      # Send as in-app message
      if channel == :message || channel == :both
        if person.user.present?
          message = MessageService.send_direct(
            sender: sender,
            recipient_person: person,
            subject: subject,
            body: body,
            production: production,
            organization: production.organization
          )
          result[:messages_sent] += 1 if message
        end
      end

      # Send as email (for :email or :both channels, or if user has no account)
      if channel == :email || channel == :both || person.user.nil?
        # Check user notification preferences
        notification_type = mailer_method == :invitation_notification ? :audition_invitations : :audition_results
        should_email = person.user.nil? || person.user.notification_enabled?(notification_type)

        if should_email
          begin
            case mailer_method
            when :invitation_notification
              Manage::AuditionMailer.invitation_notification(
                person,
                production,
                body,
                email_batch_id: email_batch&.id
              ).deliver_later
            else
              Manage::AuditionMailer.casting_notification(
                person,
                production,
                body,
                subject: subject,
                email_batch_id: email_batch&.id
              ).deliver_later
            end
            result[:emails_sent] += 1
          rescue StandardError => e
            Rails.logger.error "AuditionNotificationService: Failed to send email to #{person.email}: #{e.message}"
          end
        end
      end

      result
    end

    def default_cast_body(person, production, talent_pool)
      <<~BODY
        <p>Dear #{person.first_name || person.name},</p>

        <p>Congratulations! You have been added to the cast for <strong>#{production.name}</strong>!</p>

        <p>Please log in to your CocoScout account to view your schedule and any additional information.</p>

        <p>Welcome to the team!</p>
      BODY
    end

    def default_rejection_body(person, production)
      <<~BODY
        <p>Dear #{person.first_name || person.name},</p>

        <p>Thank you for auditioning for <strong>#{production.name}</strong>.</p>

        <p>After careful consideration, we are not able to offer you a role at this time. We appreciate your interest and encourage you to audition for future productions.</p>

        <p>Best wishes,<br>The #{production.name} Team</p>
      BODY
    end

    def default_invitation_body(person, production, audition_cycle)
      <<~BODY
        <p>Dear #{person.first_name || person.name},</p>

        <p>You have been scheduled for an audition for <strong>#{production.name}</strong>!</p>

        <p>Please log in to your CocoScout account to view your audition time and any preparation materials.</p>

        <p>We look forward to seeing you!</p>
      BODY
    end

    def default_not_invited_body(person, production)
      <<~BODY
        <p>Dear #{person.first_name || person.name},</p>

        <p>Thank you for your interest in <strong>#{production.name}</strong>.</p>

        <p>Unfortunately, we were not able to schedule you for an audition at this time. We encourage you to apply for future audition opportunities.</p>

        <p>Best wishes,<br>The #{production.name} Team</p>
      BODY
    end
  end
end
