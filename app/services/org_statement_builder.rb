# frozen_string_literal: true

# What a theater's monthly statement says, worked out from the ledgers:
#
#   What you paid CocoScout — the plan (or that it's complimentary), usage
#     bills, 50¢ a ticket with the card processing split between what buyers
#     paid and what the theater paid, course fees, less what refunds gave
#     back. From CocoScout's own ledger and the month's bills.
#   Your CocoScout balance — opening, money in by kind, money out by kind,
#     closing. From the theater's cash ledger.
class OrgStatementBuilder
  INCOME_LABELS = {
    "ticket_fee" => "Ticket fees (50¢ a ticket)", "ticket_processing" => "Card processing on tickets",
    "ticket_refund" => "Fees given back on refunds", "course_fee" => "Course fees",
    "course_refund" => "Course fees given back on refunds", "contract_processing" => "Card processing on contract payments",
    "subscription" => "Pro plan", "usage" => "Usage", "other_income" => "Other"
  }.freeze

  CASH_LABELS = {
    "ticket_sale" => "Ticket sales", "ticket_refund" => "Ticket refunds", "ticket_dispute" => "Disputed charges",
    "ticket_exchange_in" => "Tickets moved in from another date", "ticket_exchange_out" => "Tickets moved to another date",
    "course_registration" => "Course registrations", "refund" => "Course refunds", "contract_payment" => "Contract payments collected",
    "funding" => "Added from your bank for payout runs", "top_up" => "Added from your bank", "transfer" => "Paid out (payees and withdrawals)",
    "transfer_reversal" => "Payouts that came back", "opening_balance" => "Opening balance", "adjustment" => "Corrections"
  }.freeze

  def self.totals(organization, month)
    month = month.to_date.beginning_of_month
    range = month.in_time_zone.beginning_of_day...month.next_month.in_time_zone.beginning_of_day
    paid = CocoScoutLedgerEntry.where(organization: organization, occurred_at: range, entry_type: CocoScoutLedgerEntry.types_in(:income))
                               .group(:entry_type).sum(:amount_cents)
    orders = TicketOrder.where(organization: organization, money_path: "cocoscout", exchanged_from_id: nil, paid_at: range).where("total_cents > 0")
    cash = OrgCashEntry.where(organization: organization)
    moved = cash.where(occurred_at: range).group(:entry_type).sum(:amount_cents)
    opening = cash.where(occurred_at: ...range.first).sum(:amount_cents)
    bills = BillingInvoice.where(organization: organization).where("paid_at >= ? AND paid_at < ? OR (status IN ('open','uncollectible') AND period_start < ?)", range.first, range.last, range.last)

    {
      "month" => month.iso8601,
      "plan" => plan_words(organization),
      "paid" => INCOME_LABELS.keys.filter_map { |type| [ INCOME_LABELS[type], paid[type] ] if paid[type].to_i.nonzero? },
      "total_paid_cents" => paid.values.sum,
      "paid_tickets" => (orders.sum(:platform_fee_cents) / TicketPricing::PLATFORM_FEE_CENTS),
      "fees_paid_by_buyers_cents" => orders.where(fee_mode: "buyer").sum(:buyer_fee_cents),
      "fees_paid_by_you_cents" => orders.where(fee_mode: "org").sum("platform_fee_cents + processing_cents"),
      "bills" => bills.order(:period_start).map do |bill|
        { "label" => bill.label, "number" => bill.number, "period" => bill.covered_month&.strftime("%B %Y"),
          "amount_cents" => bill.amount_due_cents, "status" => bill.status_label, "lines" => bill.lines }
      end,
      "opening_cents" => opening,
      "money_in" => moved.select { |_, c| c.positive? }.map { |type, c| [ CASH_LABELS.fetch(type, type.humanize), c ] },
      "money_out" => moved.select { |_, c| c.negative? }.map { |type, c| [ CASH_LABELS.fetch(type, type.humanize), c ] },
      "closing_cents" => opening + moved.values.sum
    }
  end

  def self.plan_words(organization)
    plan = if organization.comped? then "Pro, complimentary"
    elsif organization.on_paid_plan? then organization.subscription_interval == "year" ? "Pro, yearly" : "Pro, monthly"
    else "Producer (free)"
    end
    return plan unless organization.on_paid_plan?

    "#{plan}; usage #{organization.comped_usage? ? 'complimentary' : 'billed monthly'}"
  end

  # Anything to say for this month?
  def self.activity?(organization, month)
    month = month.to_date.beginning_of_month
    range = month.in_time_zone.beginning_of_day...month.next_month.in_time_zone.beginning_of_day
    OrgCashEntry.where(organization: organization, occurred_at: range).exists? ||
      CocoScoutLedgerEntry.where(organization: organization, occurred_at: range).exists? ||
      BillingInvoice.where(organization: organization, paid_at: range).exists?
  end
end
