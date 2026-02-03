# frozen_string_literal: true

module Manage
  class ShowMailer < ApplicationMailer
    def canceled_notification(person:, show:, production:, email_subject:, email_body:, email_batch_id: nil)
      @person = person
      @show = show
      @production = production
      @email_body = email_body
      @email_batch_id = email_batch_id

      # Use custom subject if provided, otherwise render from template
      subject = if email_subject.present?
        email_subject
      else
        ContentTemplateService.render_subject("show_canceled", {
          production_name: production.name,
          event_type: show.event_type.titleize,
          event_date: show.date_and_time.strftime("%A, %B %-d, %Y")
        })
      end

      headers["X-Email-Batch-ID"] = email_batch_id.to_s if email_batch_id.present?

      mail(
        to: person.email,
        subject: subject
      )
    end
  end
end
