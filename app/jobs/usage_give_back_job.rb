# frozen_string_literal: true

# Refunds one bill that charged too much, for Finances' Refund all.
class UsageGiveBackJob < ApplicationJob
  queue_as :default

  def perform(billing_invoice_id)
    invoice = BillingInvoice.find_by(id: billing_invoice_id)
    row = invoice && UsageOverbilling.row_for(invoice)
    UsageOverbilling.give_back!(row, how: "refund") if row&.refundable_now?
  rescue Stripe::StripeError => e
    Rails.logger.warn("[UsageGiveBackJob] bill #{billing_invoice_id}: #{e.message}")
  end
end
