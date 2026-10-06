# frozen_string_literal: true

# Emails the org's owner about a CocoScout bill: when Stripe issues it ("bill")
# and when it's paid ("receipt"). Each goes once; a $0 bill sends nothing.
class BillingInvoiceEmailJob < ApplicationJob
  queue_as :default

  def perform(billing_invoice_id, which)
    invoice = BillingInvoice.find_by(id: billing_invoice_id)
    return unless invoice && invoice.amount_due_cents.positive?

    column = which == "receipt" ? :receipt_emailed_at : :bill_emailed_at
    return if invoice[column].present?
    return if which == "receipt" && invoice.status != "paid"

    owner = invoice.organization.owner
    return if owner&.email_address.blank?

    template = which == "receipt" ? "cocoscout_bill_paid" : "cocoscout_bill"
    AppMailer.with(template_key: template, to: owner.email_address, variables: BillingInvoiceEmailContent.for(invoice, owner)).send_template.deliver_now
    invoice.update_column(column, Time.current)
  end
end
