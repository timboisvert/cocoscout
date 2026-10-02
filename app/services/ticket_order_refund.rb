# frozen_string_literal: true

# Gives a ticket buyer their money back — the whole order, or some tickets.
#
# By default everything comes back: each ticket's price and tax, plus the
# fees the buyer paid. keep_fees: true returns only price and tax. Either way
# our 50¢ per ticket is never kept on a refund, so the theater's balance gives
# up that much less than the buyer gets back; Stripe keeps its processing fee,
# which comes out of the theater's money.
#
# Where the money comes from: before the show, from what that show sold (it's
# still held for exactly this); after the show, from the theater's available
# balance, and a refund it can't cover is refused rather than spending
# anything that isn't the theater's. Cash door sales are handed back from the
# cash box; comps just stop being valid.
class TicketOrderRefund
  class Error < StandardError; end

  Quote = Data.define(:tickets, :face_cents, :tax_cents, :fees_cents, :platform_fee_waived_cents, :amount_cents) do
    def org_debit_cents
      amount_cents - platform_fee_waived_cents
    end
  end

  # Once a show has started, refunds need the theater's say-so: the
  # "refunds after the show" setting is off by default.
  def self.allowed?(order)
    order.ticket_listing.show.date_and_time > Time.current || TicketingProfile.for(order.organization).refunds_after_show
  end

  def self.refundable(order)
    order.tickets.where(status: Ticket::SOLD_STATUSES).includes(:tax_lines).order(:id)
  end

  # What refunding these tickets (all of them by default) would give back.
  def self.quote(order, ticket_ids: nil, keep_fees: false)
    tickets = refundable(order).to_a
    tickets = tickets.select { |t| ticket_ids.map(&:to_i).include?(t.id) } if ticket_ids.present?

    tax = tickets.sum { |t| t.tax_lines.sum(&:tax_cents) }
    added_tax = tickets.sum { |t| t.tax_lines.reject(&:included).sum(&:tax_cents) }
    paid_for = tickets.sum { |t| t.price_cents - t.discount_cents }
    face = paid_for - (tax - added_tax)
    paid_tickets = tickets.count { |t| t.price_cents > t.discount_cents }

    fees = keep_fees ? 0 : fee_share(order, paid_tickets)
    amount = paid_for + added_tax + fees
    waived = order.platform_fee_cents.positive? ? [ TicketPricing::PLATFORM_FEE_CENTS * paid_tickets, amount ].min : 0
    Quote.new(tickets: tickets, face_cents: face, tax_cents: tax, fees_cents: fees,
              platform_fee_waived_cents: waived, amount_cents: amount)
  end

  # The buyer-paid fees that go with these tickets: their share of what's
  # left, or all of it with the order's last paid tickets.
  def self.fee_share(order, paid_tickets)
    return 0 if order.buyer_fee_cents.zero? || paid_tickets.zero?

    remaining = order.buyer_fee_cents - order.ticket_refunds.succeeded.sum(:fees_cents)
    still_paid = order.tickets.where(status: Ticket::SOLD_STATUSES).where("price_cents > discount_cents").count
    return remaining if paid_tickets >= still_paid

    [ (order.buyer_fee_cents * paid_tickets) / paid_ticket_count(order), remaining ].min
  end

  def self.paid_ticket_count(order)
    [ order.tickets.where("price_cents > discount_cents").count, 1 ].max
  end

  # allow_after_show: the show-cancellation job, which only ever starts before
  # showtime, isn't stopped by the setting if it finishes after.
  def self.issue!(order, ticket_ids: nil, keep_fees: false, by: nil, reason: nil, notify: true, allow_after_show: false)
    raise Error, "Only a paid order can be refunded." unless order.paid?
    unless allow_after_show || allowed?(order)
      raise Error, "Refunds after the show are off. You can turn them on in Ticketing settings."
    end

    quote = quote(order, ticket_ids: ticket_ids, keep_fees: keep_fees)
    raise Error, "Those tickets were already refunded." if quote.tickets.empty?

    listing = order.ticket_listing
    refund = nil
    OrgCashEntry.with_org_lock(order.organization) do
      refund = order.ticket_refunds.create!(
        organization: order.organization, refunded_by: by, reason: reason, keep_fees: keep_fees,
        ticket_ids: quote.tickets.map(&:id), amount_cents: quote.amount_cents, face_cents: quote.face_cents,
        tax_cents: quote.tax_cents, fees_cents: quote.fees_cents,
        platform_fee_waived_cents: quote.platform_fee_waived_cents, org_debit_cents: quote.org_debit_cents
      )
      reserve!(order, listing, refund) if order.money_path == "cocoscout"
    end

    if order.money_path == "cocoscout" && refund.amount_cents.positive?
      stripe_refund = Stripe::Refund.create(
        { payment_intent: order.stripe_payment_intent_id, amount: refund.amount_cents,
          metadata: { ticket_order_id: order.id, ticket_refund_id: refund.id } },
        { idempotency_key: "ticket-refund-#{refund.id}" }
      )
      refund.stripe_refund_id = stripe_refund.id
    end

    complete!(order, listing, refund)
    TicketRefundEmailJob.perform_later(refund.id) if notify && order.buyer_email.present? && refund.amount_cents.positive?
    # The theater's team hears about refunds one by one; a canceled show's
    # refunds are summed up when the cancellation finishes.
    TicketingNotifier.notify(order.organization, :refund_issued, variables: TicketingNotificationContent.refund(refund)) if notify
    refund
  rescue Stripe::StripeError => e
    OrgCashEntry.unpost!(source: refund, entry_type: "ticket_refund") if refund
    if refund
      refund.update!(status: "failed", error: e.message)
      TicketingNotifier.notify(order.organization, :refund_problem, variables: TicketingNotificationContent.refund(refund, problem: e.message))
    end
    raise Error, "Stripe couldn't refund it: #{e.message}"
  end

  # Take the refund out of the theater's money before Stripe sends it. Before
  # the show it comes out of that show's held sales; after, it has to fit in
  # the available balance.
  def self.reserve!(order, listing, refund)
    if listing.released_at.present? && refund.org_debit_cents > TicketBalance.available_cents(order.organization)
      available = TicketBalance.available_cents(order.organization)
      raise Error, "Your CocoScout balance has #{ActiveSupport::NumberHelper.number_to_currency(available / 100.0)}, " \
                   "not enough to refund #{ActiveSupport::NumberHelper.number_to_currency(refund.org_debit_cents / 100.0)}. " \
                   "Money for this show was already spent or withdrawn."
    end
    return if refund.org_debit_cents.zero?

    OrgCashEntry.post!(organization: order.organization, entry_type: "ticket_refund", amount_cents: -refund.org_debit_cents,
                       source: refund, description: "Ticket refund #{order.code}")
  end

  def self.complete!(order, listing, refund)
    ActiveRecord::Base.transaction do
      refund.update!(status: "succeeded")
      now = Time.current
      tickets = Ticket.where(id: refund.ticket_ids)
      tickets.update_all(status: order.money_path == "none" ? "void" : "refunded", refunded_at: now, updated_at: now)
      reverse_tax!(order, tickets)

      refunded = order.refunded_cents + refund.amount_cents
      left = order.tickets.where(status: Ticket::SOLD_STATUSES).exists?
      order.update!(refunded_cents: refunded, refunded_at: now, status: left ? "partially_refunded" : "refunded")
      post_books!(order, listing, refund)
    end
    TicketSalesSync.sync!(listing.show)
  end

  # Each refunded ticket's tax comes back off the theater's tax report.
  def self.reverse_tax!(order, tickets)
    TaxLine.where(taxable_type: "Ticket", taxable_id: tickets.select(:id), reversal_of_id: nil).where("tax_cents >= 0").find_each do |line|
      next if TaxLine.exists?(reversal_of_id: line.id)

      TaxLine.create!(line.attributes.except("id", "created_at", "updated_at")
                          .merge("base_cents" => -line.base_cents, "tax_cents" => -line.tax_cents,
                                 "sale_date" => Date.current, "reversal_of_id" => line.id))
    end
  end

  # The sale, taken back in proportion: money out, the show's sales and tax
  # down, the buyer's fees returned, our waived 50¢ off the fees line.
  def self.post_books!(order, listing, refund)
    return if refund.amount_cents.zero? || order.money_path == "none"

    dims = { show: listing.show, production: listing.production }
    income_account = listing.released_at.present? || order.money_path == "cash" ? :ticket_income : :advance_ticket_sales
    money_line = if order.money_path == "cash"
      { account: :door_cash, amount_cents: -refund.amount_cents }
    else
      { account: :cocoscout_balance, amount_cents: -refund.org_debit_cents }
    end
    LedgerPosting.post!(organization: order.organization, source: refund, kind: "refund",
                        entry_date: Date.current, cash_date: Date.current, memo: "Ticket refund #{order.code}",
                        lines: [
                          money_line,
                          { account: income_account, amount_cents: refund.face_cents, **dims },
                          { account: :tax_to_remit, amount_cents: refund.tax_cents, **dims },
                          { account: :fees_paid_by_buyers, amount_cents: refund.fees_cents },
                          { account: :ticketing_fees, amount_cents: -refund.platform_fee_waived_cents }
                        ])
  end

  private_class_method :fee_share, :paid_ticket_count, :reserve!, :complete!, :reverse_tax!, :post_books!
end
