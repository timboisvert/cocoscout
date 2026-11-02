# frozen_string_literal: true

# A bill Stripe just issued, looked at again once its automatic charge has
# started (about an hour after it's issued), so the bill says the money is
# on its way, and when it lands, without waiting for the nightly sweep.
class BillingInvoiceRefreshJob < ApplicationJob
  queue_as :background

  def perform(billing_invoice_id)
    record = BillingInvoice.find_by(id: billing_invoice_id)
    return unless record&.status == "open"

    BillingInvoiceSync.sync!(Stripe::Invoice.retrieve({ id: record.stripe_invoice_id, expand: [ "payments" ] }), organization: record.organization)
  rescue Stripe::StripeError => e
    Rails.logger.warn("[BillingInvoiceRefreshJob] #{billing_invoice_id}: #{e.message}")
  end
end
