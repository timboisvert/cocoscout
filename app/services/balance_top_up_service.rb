# frozen_string_literal: true

# Adds money to the theater's CocoScout balance from the bank or card it
# funds payout runs with (the same PaymentIntent shape as funding a run). A
# card lands at once; a bank debit lands when Stripe says so (the
# payment_intent webhook, metadata type "balance_top_up"). When it lands: the
# cash ledger and the books record it, and any refund waiting on it goes out.
class BalanceTopUpService
  class Error < StandardError; end

  def self.start!(organization, amount_cents:, by: nil, refund_request: nil)
    amount_cents = amount_cents.to_i
    raise Error, "Enter an amount to add." unless amount_cents.positive?
    raise Error, "Connect a bank or card in Money settings first." if organization.funding_payment_method_id.blank? || organization.stripe_customer_id.blank?

    top_up = organization.balance_top_ups.create!(amount_cents: amount_cents, requested_by: by, refund_request: refund_request)
    intent = Stripe::PaymentIntent.create(
      {
        amount: amount_cents, currency: "usd", customer: organization.stripe_customer_id,
        payment_method: organization.funding_payment_method_id,
        payment_method_types: [ organization.funding_payment_method_type.presence || "us_bank_account" ],
        confirm: true, off_session: true, transfer_group: "org_#{organization.id}",
        metadata: { type: "balance_top_up", balance_top_up_id: top_up.id, organization_id: organization.id }
      },
      { idempotency_key: "balance-top-up-#{top_up.id}" }
    )
    top_up.update!(stripe_payment_intent_id: intent.id)
    settle!(top_up) if intent.status == "succeeded"
    top_up
  rescue Stripe::StripeError => e
    top_up&.update!(status: "failed", error: e.message)
    raise Error, "Stripe couldn't take it: #{e.message}"
  end

  # The money is in. Idempotent: the webhook and the card path may both call it.
  def self.settle!(top_up)
    landed = false
    top_up.with_lock do
      next unless top_up.status == "pending"

      top_up.update!(status: "succeeded")
      OrgCashEntry.post!(organization: top_up.organization, entry_type: "top_up", amount_cents: top_up.amount_cents,
                         source: top_up, description: "Added from your bank")
      LedgerPosting.post!(organization: top_up.organization, source: top_up, kind: "top_up",
                          entry_date: Date.current, cash_date: Date.current, memo: "Added to your CocoScout balance",
                          lines: [
                            { account: :cocoscout_balance, amount_cents: top_up.amount_cents },
                            { account: :bank, amount_cents: -top_up.amount_cents }
                          ])
      landed = true
    end
    issue_waiting_refund(top_up) if landed
    top_up
  end

  def self.fail!(top_up, message)
    top_up.update!(status: "failed", error: message) if top_up.status == "pending"
  end

  def self.issue_waiting_refund(top_up)
    request = top_up.refund_request
    return if request.blank?

    order = top_up.organization.ticket_orders.find_by(id: request["order_id"])
    return unless order&.paid?

    TicketOrderRefund.issue!(order, ticket_ids: request["ticket_ids"], keep_fees: request["keep_fees"],
                                    reason: request["reason"], by: User.find_by(id: request["user_id"]))
  rescue TicketOrderRefund::Error => e
    Rails.logger.warn("[BalanceTopUpService] waiting refund for order #{request['order_id']}: #{e.message}")
  end

  private_class_method :issue_waiting_refund
end
