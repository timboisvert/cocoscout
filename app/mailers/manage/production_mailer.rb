# frozen_string_literal: true

module Manage
  class ProductionMailer < ApplicationMailer
    def send_message(recipient, subject, body_html, sender, email_batch_id: nil, production_id: nil)
      @recipient = recipient
      @person = recipient  # For find_recipient_entity and find_organization
      @message = body_html
      @sender = sender
      @production_id = production_id
      @production = Production.find_by(id: production_id) if production_id  # For find_organization

      # Track email batch if provided
      headers["X-Email-Batch-ID"] = email_batch_id if email_batch_id.present?

      # recipient is a Person, sender is a User
      recipient_email = recipient.respond_to?(:email) ? recipient.email : recipient.email_address
      sender_email = sender.respond_to?(:email_address) ? sender.email_address : sender.email

      mail(
        to: recipient_email,
        from: sender_email,
        subject: subject
      )
    end

    private

    # Override to include production_id
    def find_production_id
      @production_id
    end
  end
end
