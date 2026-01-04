# frozen_string_literal: true

module Manage
  class ContactMailer < ApplicationMailer
    def send_message(recipient, subject, message, sender, email_batch_id: nil, production_id: nil)
      @recipient = recipient
      @person = recipient # For recipient entity tracking
      @message = message
      @sender = sender
      @email_batch_id = email_batch_id
      @production_id = production_id

      mail(
        to: recipient.email,
        subject: subject
      )
    end

    private

    # Override to include email_batch_id from instance variable
    def find_email_batch_id
      @email_batch_id
    end

    # Override to include production_id from instance variable
    def find_production_id
      @production_id
    end
  end
end
