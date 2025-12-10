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
      mail(to: person.email, subject: title)
    end

    private

    # Override to include email_batch_id from instance variable
    def find_email_batch_id
      @email_batch_id
    end
  end
end
