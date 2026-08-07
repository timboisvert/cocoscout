# frozen_string_literal: true

module Manage
  # Confirms to the counterparty that a contract is fully signed, with the
  # countersigned PDF attached — the copy they keep. Distinct from
  # ContractSignatureMailer, which asks them to sign; this one is the receipt,
  # and it's the only contract email that carries an attachment.
  class ContractSignedMailer < ApplicationMailer
    def countersigned(person, subject, body, pdf_data, filename)
      return if person.email.blank?

      attachments[filename] = { mime_type: "application/pdf", content: pdf_data } if pdf_data.present?

      mail(to: person.email, subject: subject) do |format|
        format.html { render html: body.to_s.html_safe, layout: "mailer" }
      end
    end
  end
end
