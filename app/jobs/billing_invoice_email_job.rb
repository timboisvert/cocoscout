# frozen_string_literal: true

# Emails the organization's billing contacts about a CocoScout bill: when
# Stripe issues it ("bill") and when it's paid ("receipt"), with CocoScout's
# invoice attached (marked PAID on the receipt). Each goes once per bill; a $0
# bill sends nothing.
class BillingInvoiceEmailJob < ApplicationJob
  queue_as :default

  def perform(billing_invoice_id, which)
    invoice = BillingInvoice.find_by(id: billing_invoice_id)
    return unless invoice && invoice.amount_due_cents.positive?

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
end
