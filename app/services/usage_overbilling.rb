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
#
# A second bill for a month another bill already carries (two usage
# subscriptions, each billing the month: Stars & Garters, October 2026) owes
# nothing, so all of it is the overcharge.
#
# What's been given back is kept on the bill (credit_notes_cents from Stripe,
# balance_credited_cents from here), so superadmin Finances can list every
# overcharge without asking Stripe; Stripe is asked again right before
# anything is given back.
class UsageOverbilling
  Row = Data.define(:invoice, :month, :staff, :performers, :owed_cents, :charged_cents, :credited_cents, :duplicate) do
    def over_cents = [ charged_cents - credited_cents - owed_cents, 0 ].max

    # Paid: it can go back to the card or bank now. Still being collected:
    # once the money lands (lands_on).
    def refundable_now? = invoice.status == "paid" && over_cents.positive?
    def lands_on = invoice.lands_on
  end

  def self.rows(organization)
    duplicates = BillingInvoice.duplicate_ids
    BillingInvoice.where(organization: organization, kind: "usage").order(:period_start, :id).filter_map do |invoice|
      next unless invoice.status == "paid" || invoice.collecting?

      month = UsageInvoiceCorrection.billed_month(invoice)
      next unless month

      staff = UsageRules.staff(month, organization: organization).fetch(organization.id, {}).size
      performers = UsageRules.performers(month, organization: organization).fetch(organization.id, {}).size
      duplicate = duplicates.include?(invoice.id)
      owed = duplicate ? 0 : staff * StaffBillingService::PER_ACTIVE_STAFF_CENTS + performers * PerformerBillingService::PER_ACTIVE_PERFORMER_CENTS +
                             UsageRules.bank_debit_fee_cents(organization, month)
      Row.new(invoice: invoice, month: month, staff: staff, performers: performers, owed_cents: owed, duplicate: duplicate,
              charged_cents: invoice.status == "paid" ? invoice.amount_paid_cents : invoice.amount_due_cents,
              credited_cents: invoice.credit_notes_cents + invoice.balance_credited_cents)
    end
  end

  # Every overcharge not yet given back, across every organization billed
  # for usage, oldest first.
  def self.all_rows
    Organization.where(id: BillingInvoice.where(kind: "usage").select(:organization_id)).order(:name)
                .flat_map { |organization| rows(organization) }.select { |row| row.over_cents.positive? }
  end

  def self.row_for(invoice)
    rows(invoice.organization).find { |row| row.invoice.id == invoice.id }
  end

  # What Stripe says has been given back for the bill: credit notes on it,
  # plus balance credits given while it was being collected.
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

    # Ask Stripe what's been given back already, in case this bill was just
    # given back from another tab or the console.
    cents = [ row.charged_cents - credited_cents(row.invoice) - row.owed_cents, 0 ].max
    return nil unless cents.positive?

    words = if row.duplicate
      "#{row.month.strftime('%B %Y')} usage was billed twice; this bill is given back in full"
    else
      "Usage for #{row.month.strftime('%B %Y')} corrected to paid work: #{row.staff} staff and #{row.performers} performers"
    end
    if row.invoice.collecting?
      return nil if how == "refund"

      result = Stripe::Customer.create_balance_transaction(
        row.invoice.organization.stripe_customer_id,
        { amount: -cents, currency: "usd", description: "#{words} (bill #{row.invoice.number})",
          metadata: { kind: "usage_overbilled", usage_overbilled_invoice: row.invoice.stripe_invoice_id, month: row.month.iso8601 } },
        { idempotency_key: "usage-overbilled-balance-#{row.invoice.stripe_invoice_id}-#{cents}" }
      )
      row.invoice.increment!(:balance_credited_cents, cents)
      return result
    end
    params = {
      invoice: row.invoice.stripe_invoice_id,
      lines: [ { type: "custom_line_item", description: words, quantity: 1, unit_amount: cents } ],
      memo: row.duplicate ? "#{words}. We're sorry for the extra charge." : "#{words}. You were charged more than that; this gives back the difference.",
      metadata: { kind: "usage_overbilled", month: row.month.iso8601 }
    }
    params[how == "refund" ? :refund_amount : :credit_amount] = cents
    note = Stripe::CreditNote.create(params, { idempotency_key: "usage-overbilled-#{row.invoice.stripe_invoice_id}-#{cents}" })
    row.invoice.increment!(:credit_notes_cents, cents)
    note
  end
end
