# frozen_string_literal: true

module Manage
  class CastingMailer < ApplicationMailer
    def cast_email(person, show, title, body, sender, email_batch_id: nil)
      @person = person
      @show = show
      @title = title
      @body = body
      @sender = sender
      @email_batch_id = email_batch_id

      headers["X-Email-Batch-ID"] = email_batch_id.to_s if email_batch_id.present?

      mail(to: person.email, subject: title)
    end

    # Notification when someone is cast in a show
    def cast_notification(person, show, email_body, subject, email_batch_id: nil)
      @person = person
      @show = show
      @production = show.production
      @email_body = email_body
      @email_batch_id = email_batch_id

      headers["X-Email-Batch-ID"] = email_batch_id.to_s if email_batch_id.present?

      mail(
        to: person.email,
        subject: subject
      )
    end

    # Notification when someone is removed from a cast
    def removed_notification(person, show, email_body, subject, email_batch_id: nil)
      @person = person
      @show = show
      @production = show.production
      @email_body = email_body
      @email_batch_id = email_batch_id

      headers["X-Email-Batch-ID"] = email_batch_id.to_s if email_batch_id.present?

      mail(
        to: person.email,
        subject: subject
      )
    end

    private

    # Override to include email_batch_id from instance variable
    def find_email_batch_id
      @email_batch_id
    end
  end
end
