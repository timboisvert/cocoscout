# frozen_string_literal: true

module Manage
  class ProductionMailer < ApplicationMailer
    def send_message(recipient, subject, body_html, sender, email_batch_id: nil, production_id: nil)
      @recipient = recipient
      @message = body_html
      @sender = sender
      @production_id = production_id

      # Track email batch if provided
      headers["X-Email-Batch-ID"] = email_batch_id if email_batch_id.present?

      mail(
        to: recipient.email,
        from: sender.email,
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
