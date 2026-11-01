# frozen_string_literal: true

# Gives back one bill that charged too much, for Finances' Refund all and
# Credit all: how is "refund" or "credit".
class UsageGiveBackJob < ApplicationJob
  queue_as :default

  def perform(billing_invoice_id, how = "refund")
    invoice = BillingInvoice.find_by(id: billing_invoice_id)
    row = invoice && UsageOverbilling.row_for(invoice)
    UsageOverbilling.give_back!(row, how: how) if row&.refundable_now?
  rescue Stripe::StripeError => e
    Rails.logger.warn("[UsageGiveBackJob] bill #{billing_invoice_id}: #{e.message}")
  end
end
