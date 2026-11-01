# frozen_string_literal: true

# Makes each usage bill equal what CocoScout says the org owes: $5 for every
# staff member and $3 for every performer it paid through Stripe in the month
# the bill covers (StaffActivation / PerformerActivation). Stripe's meter does
# the counting, but what it has counted can't be taken back (the meter took
# October 2026's scheduled-but-unpaid staff before the rule was fixed), and a
# usage period that doesn't start on the 1st straddles two months. So when
# Stripe drafts a usage bill (invoice.created, and Stripe holds the bill until
# our webhook answers), the difference goes on it as one correction line,
# and bank debits beyond the month's free ones and withdrawals over the free
# amount go on it as their own lines.
class UsageInvoiceCorrection
  PREFIX = "Correction:"

  def self.apply!(record)
    return unless record&.kind == "usage" && record.status == "draft"

    organization = record.organization
    month = billed_month(record)
    return if month.nil? || organization.stripe_customer_id.blank?

    staff = StaffActivation.where(organization: organization).for_month(month).count
    performers = PerformerActivation.where(organization: organization).for_month(month).count
    expected = staff * StaffBillingService::PER_ACTIVE_STAFF_CENTS + performers * PerformerBillingService::PER_ACTIVE_PERFORMER_CENTS
    # A month bills once. A second bill for it (a second usage subscription)
    # is corrected to nothing, never topped up to the month again.
    expected = 0 if record.duplicate?
    on_bill = record.lines.sum { |line| line["amount_cents"].to_i }
    difference = expected - on_bill
    unless record.duplicate?
      add_bank_debit_fee!(record, organization, month)
      add_withdrawal_fee!(record, organization, month)
    end
    return if difference.zero?

    people = UsageRules.by_payment?(month) ? "#{staff} staff and #{performers} others paid" : "#{staff} staff and #{performers} performers paid"
    Stripe::InvoiceItem.create(
      { customer: organization.stripe_customer_id, invoice: record.stripe_invoice_id, amount: difference, currency: "usd",
        description: "#{PREFIX} #{people} through CocoScout in #{month.strftime('%B %Y')}",
        metadata: { kind: "usage_correction", organization_id: organization.id, month: month.iso8601 } },
      { idempotency_key: "usage-correction-#{record.stripe_invoice_id}-#{difference}" }
    )
  end

  # Withdrawals over the month's free amount: our payment provider's 0.25% on
  # the part over, as its own line.
  def self.add_withdrawal_fee!(record, organization, month)
    withdrawn = UsageRules.withdrawn_cents(organization, month)
    fee = UsageRules.withdrawal_fee_cents(organization, month, withdrawn)
    return if fee.zero?

    over = ActiveSupport::NumberHelper.number_to_currency((withdrawn - UsageRules::FREE_WITHDRAWAL_CENTS) / 100.0)
    Stripe::InvoiceItem.create(
      { customer: organization.stripe_customer_id, invoice: record.stripe_invoice_id, currency: "usd", amount: fee,
        description: "Withdrawals over #{ActiveSupport::NumberHelper.number_to_currency(UsageRules::FREE_WITHDRAWAL_CENTS / 100.0, precision: 0)} " \
                     "in #{month.strftime('%B %Y')}: 0.25% of #{over}, our payment provider's cost",
        metadata: { kind: "withdrawal_fee", organization_id: organization.id, month: month.iso8601, withdrawn_cents: withdrawn } },
      { idempotency_key: "withdrawal-fee-#{record.stripe_invoice_id}-#{fee}" }
    )
  end

  # Bank debits beyond the free ones that month, at a flat fee each, as their
  # own line on the month's usage bill.
  def self.add_bank_debit_fee!(record, organization, month)
    extra = UsageRules.extra_bank_debits(organization, month)
    return if extra.zero?

    Stripe::InvoiceItem.create(
      { customer: organization.stripe_customer_id, invoice: record.stripe_invoice_id, currency: "usd",
        amount: extra * UsageRules::EXTRA_BANK_DEBIT_CENTS,
        description: "#{extra} bank #{extra == 1 ? 'debit' : 'debits'} beyond the #{UsageRules::FREE_BANK_DEBITS} free in #{month.strftime('%B %Y')}, " \
                     "$#{UsageRules::EXTRA_BANK_DEBIT_CENTS / 100} each",
        metadata: { kind: "bank_debit_fee", organization_id: organization.id, month: month.iso8601, debits: extra } },
      { idempotency_key: "bank-debit-fee-#{record.stripe_invoice_id}-#{extra}" }
    )
  end

  # The month a bill mostly covers: the middle of its period. (A usage period
  # starting on the 30th is that next month; one starting on the 1st is that
  # month.)
  def self.billed_month(record)
    return nil unless record.period_start && record.period_end

    middle = record.period_start + ((record.period_end - record.period_start) / 2)
    middle.in_time_zone.to_date.beginning_of_month
  end
end
