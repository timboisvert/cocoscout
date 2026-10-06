# frozen_string_literal: true

# Posts CocoScout's own share of every money event to its ledger
# (CocoScoutLedgerEntry), from the record that caused it. The rule is the
# same everywhere: of what a buyer paid, the theater's share is what its cash
# ledger (OrgCashEntry) was credited, and CocoScout's share is the rest;
# what Stripe charged to process it comes out of CocoScout's share.
#
#   TicketOrder          ticket fee (50¢ a ticket), the card processing it
#                        charged, Stripe's processing
#   TicketRefund         the fees that went back to the buyer
#   CourseRegistration   the course fee, Stripe's processing; on a refund,
#                        the fee that went back
#   ContractPayment      collected online: the processing passed on to the
#                        theater, Stripe's processing (they cancel out)
#   BillingInvoice       a paid Pro or usage bill
#   OrgPayout            a theater paid by hand from CocoScout's bank: the
#                        Stripe money its balance gave up is CocoScout's
#   StripeBalanceTransaction
#                        Stripe's own fees, payouts to CocoScout's bank, the
#                        bank-debit fee on run funding and top-ups, the
#                        processing on a bill, a bill refunded, and lines a
#                        superadmin explained by hand
#
# Idempotent: each call restates the source's entries from scratch.
class CocoScoutLedgerPoster
  TYPES_FOR = {
    "TicketOrder" => %w[ticket_fee ticket_processing processing_cost],
    "TicketPassHolding" => %w[ticket_fee ticket_processing processing_cost ticket_refund],
    "TicketRefund" => %w[ticket_refund],
    "CourseRegistration" => %w[course_fee processing_cost course_refund],
    "ContractPayment" => %w[contract_processing processing_cost],
    "BillingInvoice" => %w[subscription usage],
    "OrgPayout" => %w[paid_by_hand],
    "StripeBalanceTransaction" => %w[stripe_fee other_income payout_to_bank added_from_bank funding_cost processing_cost subscription usage explained]
  }.freeze

  # Sources an OrgCashEntry can point at whose CocoScout share depends on it.
  CASH_SOURCES = %w[TicketOrder TicketPassHolding TicketRefund CourseRegistration ContractPayment OrgPayout].freeze

  def self.post_for!(record)
    return if record.nil?

    types = TYPES_FOR[record.class.name]
    return unless types

    wanted = record.destroyed? ? {} : entries_for(record)
    occurred_at = occurred_at_for(record)
    organization = record.is_a?(StripeBalanceTransaction) ? record.organization : StripeTransactionMatcher.organization_for(record)
    CocoScoutLedgerEntry.transaction do
      types.each do |type|
        CocoScoutLedgerEntry.post!(source: record, entry_type: type, amount_cents: wanted.fetch(type, 0),
                                   occurred_at: occurred_at, organization: organization,
                                   description: description_for(record))
      end
    end
  rescue StandardError => e
    raise if Rails.env.test?

    Rails.logger.error("[CocoScoutLedgerPoster] #{record.class.name} #{record.id}: #{e.class}: #{e.message}")
  end

  # An OrgCashEntry moved: its source's CocoScout share moves with it.
  def self.cash_entry_changed!(entry)
    return unless CASH_SOURCES.include?(entry.source_type)

    record = entry.source_type.constantize.find_by(id: entry.source_id)
    if record
      post_for!(record)
    else
      # The record is gone (a hand payment deleted): so is CocoScout's share of it.
      CocoScoutLedgerEntry.where(source_type: entry.source_type, source_id: entry.source_id).destroy_all
    end
  end

  def self.entries_for(record)
    case record
    when TicketOrder then ticket_order(record)
    when TicketPassHolding then pass_holding(record)
    when TicketRefund then ticket_refund(record)
    when CourseRegistration then course_registration(record)
    when ContractPayment then contract_payment(record)
    when BillingInvoice then billing_invoice(record)
    when OrgPayout then org_payout(record)
    when StripeBalanceTransaction then stripe_line(record)
    else {}
    end
  end

  def self.cash(record, type)
    OrgCashEntry.find_by(source_type: record.class.polymorphic_name, source_id: record.id, entry_type: type)&.amount_cents
  end

  # The theater was credited its net; the rest of what the buyer paid is
  # ours: the 50¢ a ticket, and the processing (charged to the buyer, or
  # taken from the theater's net when it absorbs the fees).
  def self.ticket_order(order)
    return {} if order.exchanged_from_id || order.money_path != "cocoscout"

    credit = cash(order, "ticket_sale")
    return {} if credit.nil?

    { "ticket_fee" => order.platform_fee_cents.to_i,
      "ticket_processing" => order.total_cents.to_i - credit - order.platform_fee_cents.to_i,
      "processing_cost" => -order.stripe_fee_cents.to_i }
  end

  # A credit pass, like a ticket order: our 50¢ a credit, and the processing.
  def self.pass_holding(holding)
    credit = cash(holding, "pass_sale")
    return {} if credit.nil?

    { "ticket_fee" => holding.platform_fee_cents.to_i,
      "ticket_processing" => holding.total_cents.to_i - credit - holding.platform_fee_cents.to_i,
      "processing_cost" => -holding.stripe_fee_cents.to_i,
      # Refunded: the buyer got back more than the organization gave up.
      "ticket_refund" => -(holding.refunded_cents.to_i - holding.refund_org_debit_cents.to_i) }
  end

  # The buyer got back more than the theater gave up: the difference is the
  # fees we returned (our 50¢ and, unless the theater kept them, processing).
  def self.ticket_refund(refund)
    debit = cash(refund, "ticket_refund")
    return {} if debit.nil?

    { "ticket_refund" => -(refund.amount_cents.to_i + debit) }
  end

  def self.course_registration(registration)
    credit = cash(registration, "course_registration")
    return {} if credit.nil?

    paid = registration.amount_cents.to_i + registration.tax_cents.to_i
    entries = { "course_fee" => paid - credit, "processing_cost" => -registration.stripe_fee_cents.to_i }
    if (back = cash(registration, "refund"))
      # Refunds return everything the student paid; the theater gave back its net.
      entries["course_refund"] = -(paid + back)
    end
    entries
  end

  def self.contract_payment(payment)
    credit = cash(payment, "contract_payment")
    return {} if credit.nil?

    { "contract_processing" => payment.amount_cents - credit, "processing_cost" => -payment.stripe_fee_cents.to_i }
  end

  def self.billing_invoice(invoice)
    return {} unless invoice.status == "paid"

    { (invoice.kind == "usage" ? "usage" : "subscription") => invoice.amount_paid_cents.to_i }
  end

  # CocoScout paid the theater from its own bank; the money the theater's
  # balance gave up stays in Stripe, and it's CocoScout's.
  def self.org_payout(payout)
    debit = cash(payout, "adjustment")
    debit.nil? ? {} : { "paid_by_hand" => -debit }
  end

  def self.stripe_line(row)
    entries = case row.category
    when "stripe_fee" then { "stripe_fee" => row.net_cents }
    when "other_income" then { "other_income" => row.net_cents }
    when "payout_to_bank" then { "payout_to_bank" => row.net_cents }
    when "added_from_bank" then { "added_from_bank" => row.net_cents }
    # Charges whose record keeps no Stripe fee: what Stripe took is ours to bear.
    when "run_funding", "top_up" then { "funding_cost" => -row.fee_cents }
    when "billing" then { "processing_cost" => -row.fee_cents }
    # A bill given back: the income it brought, taken back, under that org.
    when "billing_refund" then { (row.matched.try(:kind) == "usage" ? "usage" : "subscription") => row.amount_cents }
    else {}
    end
    return entries unless row.match_status == "explained"

    # Explained by hand: a line nothing explained counts whole; a line whose
    # amount disagreed with its record counts only the difference (the record
    # already posts its own amount).
    explained = row.matched_id && row.expected_cents ? row.amount_cents - row.expected_cents : row.net_cents
    entries.merge("explained" => explained)
  end

  def self.occurred_at_for(record)
    case record
    when TicketOrder, TicketPassHolding then record.paid_at || record.created_at
    when CourseRegistration then record.paid_at || record.registered_at || record.created_at
    when ContractPayment then record.paid_date&.in_time_zone || record.updated_at
    when BillingInvoice then record.paid_at || record.finalized_at || record.created_at
    when StripeBalanceTransaction then record.occurred_at
    else record.created_at
    end || Time.current
  end

  def self.description_for(record)
    case record
    when TicketOrder then "Ticket order #{record.code}"
    when TicketPassHolding then "Pass #{record.ticket_pass.name} ##{record.id}"
    when TicketRefund then "Ticket refund, order ##{record.ticket_order_id}"
    when CourseRegistration then "Course registration ##{record.id}"
    when ContractPayment then "Contract payment ##{record.id}"
    when BillingInvoice then [ record.label, record.number ].compact.join(" ")
    when OrgPayout then "Paid #{record.organization&.name} by hand (payout ##{record.id})"
    when StripeBalanceTransaction then record.description.presence || record.category_label
    end
  end

  private_class_method :entries_for, :cash, :ticket_order, :pass_holding, :ticket_refund, :course_registration, :contract_payment,
                       :billing_invoice, :org_payout, :stripe_line, :occurred_at_for, :description_for
end
