# frozen_string_literal: true

# Emails a gift certificate to the person it's for, off the request thread.
class TicketGiftCertificateEmailJob < ApplicationJob
  queue_as :default

  def perform(certificate_id)
    certificate = TicketGiftCertificate.find_by(id: certificate_id)
    return unless certificate && !certificate.voided? && certificate.recipient_email.present?

    TicketGiftCertificateMailer.issued(certificate).deliver_now
    certificate.update_columns(emailed_at: Time.current)
  end
end
