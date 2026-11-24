# frozen_string_literal: true

# Emails the organization's billing contacts about a CocoScout bill: when
# Stripe issues it ("bill") and when it's paid ("receipt"), with CocoScout's
# invoice attached (marked PAID on the receipt). Each goes once per bill; a $0
# bill sends nothing.
#
# "failed" is the payment not going through (Tim, 2026-11-24: Stripe's own
# emails are off): one email for each failed attempt, stating when the
# payment is tried again, or that it won't be.
class BillingInvoiceEmailJob < ApplicationJob
  queue_as :default

  def perform(billing_invoice_id, which)
    invoice = BillingInvoice.find_by(id: billing_invoice_id)
    return unless invoice && invoice.amount_due_cents.positive?
    return payment_failed(invoice) if which == "failed"

    column = which == "receipt" ? :receipt_emailed_at : :bill_emailed_at
    return if invoice[column].present?
    return if which == "receipt" && invoice.status != "paid"

    contacts = invoice.organization.billing_contacts
    return if contacts.empty?

    template = which == "receipt" ? "cocoscout_bill_paid" : "cocoscout_bill"
    pdf = { CocoScoutInvoice.filename(invoice) => InvoicePdf.new(CocoScoutInvoice.document(invoice)).render }
    contacts.each do |contact|
      AppMailer.with(template_key: template, to: contact.email, variables: BillingInvoiceEmailContent.for(invoice, contact.first_name),
                     attachments: pdf).send_template.deliver_now
    end
    invoice.update_column(column, Time.current)
  end

  private

  # Stripe can deliver one failure twice, and the bill may have been paid by
  # the time this runs: the attempt it emailed about is remembered, and a
  # bill that's no longer failed sends nothing.
  def payment_failed(invoice)
    return unless invoice.failed?

    retry_on = invoice.next_payment_attempt_at if invoice.status == "open" && invoice.next_payment_attempt_at&.future?
    attempt = retry_on ? retry_on.utc.iso8601 : "final"
    return if invoice.failure_emailed_for.in?([ attempt, "final" ])

    contacts = invoice.organization.billing_contacts
    return if contacts.empty?

    next_step = if retry_on
      "It will be tried again on #{retry_on.in_time_zone(invoice.organization.time_zone.presence || Time.zone.name).strftime('%B %-d')}. If the payment method on file needs to change, update it before then."
    else
      "It won't be tried again, so the bill stays unpaid until you pay it."
    end
    contacts.each do |contact|
      variables = BillingInvoiceEmailContent.for(invoice, contact.first_name).merge("next_step" => next_step)
      AppMailer.with(template_key: "cocoscout_payment_failed", to: contact.email, variables: variables).send_template.deliver_now
    end
    invoice.update_column(:failure_emailed_for, attempt)
  end
end
