# frozen_string_literal: true

module Manage
  class ContactMailer < ApplicationMailer
    def send_message(recipient, subject, message, sender)
      @recipient = recipient
      @message = message
      @sender = sender

      mail(
        to: recipient.email,
        subject: subject
      )
    end
  end
end
