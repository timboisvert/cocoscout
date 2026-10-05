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
#   StripeBalanceTransaction
#                        Stripe's own fees, payouts to CocoScout's bank, the
#                        bank-debit fee on run funding and top-ups, the
#                        processing on a bill, and lines a superadmin
#                        explained by hand
#
# Idempotent: each call restates the source's entries from scratch.
class CocoScoutLedgerPoster
  TYPES_FOR = {
    "TicketOrder" => %w[ticket_fee ticket_processing processing_cost],
    "TicketRefund" => %w[ticket_refund],
    "CourseRegistration" => %w[course_fee processing_cost course_refund],
    "ContractPayment" => %w[contract_processing processing_cost],
    "BillingInvoice" => %w[subscription usage],
    "StripeBalanceTransaction" => %w[stripe_fee other_income payout_to_bank added_from_bank funding_cost processing_cost explained]
  }.freeze

  # Sources an OrgCashEntry can point at whose CocoScout share depends on it.
  CASH_SOURCES = %w[TicketOrder TicketRefund CourseRegistration ContractPayment].freeze

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

    post_for!(entry.source_type.constantize.find_by(id: entry.source_id))
  end

  def self.entries_for(record)
    case record
    when TicketOrder then ticket_order(record)
    when TicketRefund then ticket_refund(record)
    when CourseRegistration then course_registration(record)
    when ContractPayment then contract_payment(record)
    when BillingInvoice then billing_invoice(record)
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

  def self.stripe_line(row)
    return { "explained" => row.net_cents } if row.match_status == "explained"

    case row.category
    when "stripe_fee" then { "stripe_fee" => row.net_cents }
    when "other_income" then { "other_income" => row.net_cents }
    when "payout_to_bank" then { "payout_to_bank" => row.net_cents }
    when "added_from_bank" then { "added_from_bank" => row.net_cents }
    # Charges whose record keeps no Stripe fee: what Stripe took is ours to bear.
    when "run_funding", "top_up" then { "funding_cost" => -row.fee_cents }
    when "billing" then { "processing_cost" => -row.fee_cents }
    else {}
    end
  end

  def self.occurred_at_for(record)
    case record
    when TicketOrder then record.paid_at || record.created_at
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
    when TicketRefund then "Ticket refund, order ##{record.ticket_order_id}"
    when CourseRegistration then "Course registration ##{record.id}"
    when ContractPayment then "Contract payment ##{record.id}"
    when BillingInvoice then [ record.label, record.number ].compact.join(" ")
    when StripeBalanceTransaction then record.description.presence || record.category_label
    end
  end

  private_class_method :entries_for, :cash, :ticket_order, :ticket_refund, :course_registration, :contract_payment,
                       :billing_invoice, :stripe_line, :occurred_at_for, :description_for
end
