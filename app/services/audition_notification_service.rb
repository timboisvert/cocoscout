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

      # Use custom content if provided, otherwise render from template
      if custom_body.present? || custom_subject.present?
        subject = custom_subject.presence || "Welcome to the #{production.name} cast!"
        body = custom_body.presence || render_template_body(template_key, person, production, talent_pool)
      else
        rendered = ContentTemplateService.render(template_key, {
          recipient_name: person.first_name || person.name,
          production_name: production.name,
          talent_pool_name: talent_pool&.name
        })
        subject = rendered[:subject]
        body = rendered[:body]
      end

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

      # Use custom content if provided, otherwise render from template
      if custom_body.present? || custom_subject.present?
        subject = custom_subject.presence || "Audition results for #{production.name}"
        body = custom_body.presence || render_template_body(template_key, person, production)
      else
        rendered = ContentTemplateService.render(template_key, {
          recipient_name: person.first_name || person.name,
          production_name: production.name
        })
        subject = rendered[:subject]
        body = rendered[:body]
      end

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

      # Use custom content if provided, otherwise render from template
      if custom_body.present? || custom_subject.present?
        subject = custom_subject.presence || "#{production.name} Auditions"
        body = custom_body.presence || render_template_body(template_key, person, production, nil, audition_cycle)
      else
        rendered = ContentTemplateService.render(template_key, {
          recipient_name: person.first_name || person.name,
          production_name: production.name,
          audition_cycle_name: audition_cycle&.name
        })
        subject = rendered[:subject]
        body = rendered[:body]
      end

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

      # Use custom content if provided, otherwise render from template
      if custom_body.present? || custom_subject.present?
        subject = custom_subject.presence || "Audition update for #{production.name}"
        body = custom_body.presence || render_template_body(template_key, person, production)
      else
        rendered = ContentTemplateService.render(template_key, {
          recipient_name: person.first_name || person.name,
          production_name: production.name
        })
        subject = rendered[:subject]
        body = rendered[:body]
      end

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
    # All audition notifications are message-only (no email)
    def send_notification(template_key:, subject:, body:, production:, sender:,
                          person:, message_type:, visibility:, email_batch:,
                          mailer_method: :casting_notification)
      result = { messages_sent: 0, emails_sent: 0 }

      return result unless person&.email.present?

      # Audition notifications are message-only - only send to users with accounts
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

      result
    end

    # Helper to render template body for fallback when custom subject but no custom body
    def render_template_body(template_key, person, production, talent_pool = nil, audition_cycle = nil)
      rendered = ContentTemplateService.render(template_key, {
        recipient_name: person.first_name || person.name,
        production_name: production.name,
        talent_pool_name: talent_pool&.name,
        audition_cycle_name: audition_cycle&.name
      })
      rendered[:body]
    end
  end
end
