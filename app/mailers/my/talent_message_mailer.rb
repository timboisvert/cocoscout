# frozen_string_literal: true

module My
  class TalentMessageMailer < ApplicationMailer
    def send_to_production(sender:, production:, subject:, body_html:)
      @sender = sender
      @production = production
      @message = body_html
      @production_id = production.id

      mail(
        to: production.contact_email,
        reply_to: sender.email,
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
