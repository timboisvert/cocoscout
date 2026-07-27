# frozen_string_literal: true

module Manage
  # Emails a payer their outstanding-payment reminder. The body arrives already
  # rendered by ContentTemplateService (pay link and amount interpolated in), so
  # this mailer just wraps it in the standard layout. Signature matches what
  # ContentTemplateService#deliver_as_email calls:
  #   mailer_class.send(method, person, production, body, subject, email_batch_id:)
  class ContractPaymentMailer < ApplicationMailer
    def payment_reminder(person, production, body, subject, email_batch_id: nil)
      @person = person
      @production = production
      @body = body
      @subject = subject
      @email_batch_id = email_batch_id

      return if person.email.blank?

      mail(to: person.email, subject: subject) do |format|
        format.html { render html: @body.html_safe, layout: "mailer" }
      end
    end

    private

    def find_email_batch_id
      @email_batch_id
    end
  end
end
