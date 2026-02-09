# frozen_string_literal: true

module Manage
  class AuditionMailer < ApplicationMailer
    def casting_notification(person, production, email_body, subject: nil, email_batch_id: nil)
      @person = person
      @production = production
      @email_body = email_body
      @email_batch_id = email_batch_id

      headers["X-Email-Batch-ID"] = email_batch_id.to_s if email_batch_id.present?

      # Use provided subject or fall back to template
      email_subject = subject.presence || ContentTemplateService.render_subject("audition_added_to_cast", { production_name: production.name })

      mail(
        to: person.email,
        subject: email_subject
      )
    end

    def invitation_notification(person, production, email_body, email_batch_id: nil)
      @person = person
      @production = production
      @email_body = email_body
      @email_batch_id = email_batch_id

      headers["X-Email-Batch-ID"] = email_batch_id.to_s if email_batch_id.present?

      mail(
        to: person.email,
        subject: ContentTemplateService.render_subject("audition_invitation", { production_name: production.name })
      )
    end

    def audition_request_notification(recipient_user, audition_request)
      @recipient = recipient_user
      @audition_request = audition_request
      @requestable = audition_request.requestable
      @production = audition_request.audition_cycle.production
      @audition_cycle = audition_request.audition_cycle

      mail(
        to: recipient_user.email_address,
        subject: ContentTemplateService.render_subject("audition_request_submitted", { requestable_name: @requestable.name, production_name: @production.name })
      )
    end

    def talent_left_production(recipient_user, production, person, groups)
      @recipient = recipient_user
      @production = production
      @person = person
      @groups = groups

      mail(
        to: recipient_user.email_address,
        subject: ContentTemplateService.render_subject("talent_left_production", { person_name: @person.name, production_name: @production.name })
      )
    end

    private

    def find_email_batch_id
      @email_batch_id
    end
  end
end
