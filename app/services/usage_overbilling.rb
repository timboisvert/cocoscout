# frozen_string_literal: true

# Usage bills charged more than UsageRules allows (bills from before the rule
# was fixed: staff billed for being scheduled, the old $1-per-payment fee, a
# usage period straddling two months). For each paid usage bill: the month it
# covers, what the rule says was owed for that month, what was charged less
# any credit already given, and the overcharge. Giving it back is a Stripe
# credit note on that bill for exactly the overcharge, either refunded to the
# card or bank it was paid from (CocoScout's books then take the income back,
# see StripeTransactionMatcher's billing_refund) or credited to the
# customer's Stripe balance, which pays down their next bills.
class UsageOverbilling
  Row = Data.define(:invoice, :month, :staff, :performers, :owed_cents, :charged_cents, :credited_cents) do
    def over_cents = [ charged_cents - credited_cents - owed_cents, 0 ].max
  end

  def self.rows(organization)
    BillingInvoice.where(organization: organization, kind: "usage").order(:period_start).filter_map do |invoice|
      next unless invoice.status == "paid" || invoice.collecting?

      month = UsageInvoiceCorrection.billed_month(invoice)
      next unless month

      staff = UsageRules.staff(month, organization: organization).fetch(organization.id, {}).size
      performers = UsageRules.performers(month, organization: organization).fetch(organization.id, {}).size
      owed = staff * StaffBillingService::PER_ACTIVE_STAFF_CENTS + performers * PerformerBillingService::PER_ACTIVE_PERFORMER_CENTS
      Row.new(invoice: invoice, month: month, staff: staff, performers: performers, owed_cents: owed,
              charged_cents: invoice.status == "paid" ? invoice.amount_paid_cents : invoice.amount_due_cents,
              credited_cents: credited_cents(invoice))
    end
  end

  # What has already been given back for the bill: Stripe credit notes on it,
  # plus balance credits this task gave while it was being collected.
  def self.credited_cents(invoice)
    stripe = Stripe::Invoice.retrieve(invoice.stripe_invoice_id).to_hash
    notes = stripe[:post_payment_credit_notes_amount].to_i + stripe[:pre_payment_credit_notes_amount].to_i
    balance = Stripe::Customer.list_balance_transactions(invoice.organization.stripe_customer_id, { limit: 100 }).auto_paging_each.sum do |txn|
      meta = txn.to_hash[:metadata] || {}
      meta[:usage_overbilled_invoice] == invoice.stripe_invoice_id ? -txn.amount : 0
    end
    notes + balance
  end

  # how: "refund" (back to the card or bank) or "credit" (their Stripe balance).
  # A bill still being collected can't take a credit note yet, so "credit"
  # puts the overcharge on the customer's balance now (it pays down their
  # next bills); "refund" waits until the money has landed.
  def self.give_back!(row, how:)
    raise ArgumentError, "how must be refund or credit" unless %w[refund credit].include?(how)
    return nil unless row.over_cents.positive?

    cents = row.over_cents
    words = "Usage for #{row.month.strftime('%B %Y')} corrected to paid work: #{row.staff} staff and #{row.performers} performers"
    if row.invoice.collecting?
      return nil if how == "refund"

      return Stripe::Customer.create_balance_transaction(
        row.invoice.organization.stripe_customer_id,
        { amount: -cents, currency: "usd", description: "#{words} (bill #{row.invoice.number})",
          metadata: { kind: "usage_overbilled", usage_overbilled_invoice: row.invoice.stripe_invoice_id, month: row.month.iso8601 } },
        { idempotency_key: "usage-overbilled-balance-#{row.invoice.stripe_invoice_id}-#{cents}" }
      )
    end
    params = {
      invoice: row.invoice.stripe_invoice_id,
      lines: [ { type: "custom_line_item", description: words, quantity: 1, unit_amount: cents } ],
      memo: "#{words}. You were charged more than that; this gives back the difference.",
      metadata: { kind: "usage_overbilled", month: row.month.iso8601 }
    }
    params[how == "refund" ? :refund_amount : :credit_amount] = cents
    Stripe::CreditNote.create(params, { idempotency_key: "usage-overbilled-#{row.invoice.stripe_invoice_id}-#{cents}" })
  end
end
