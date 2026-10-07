# frozen_string_literal: true

# Credit passes (Tim, 2026-10-05): a punch card or a season pass, bought now,
# used later.
#
#   start!   a checkout for N passes (no seats yet), priced and taxed now:
#            our 50¢ is per credit, processing once.
#   settle!  paid: the pass is live. Its money goes to the organization's
#            balance but stays held (TicketBalance) until the pass ends, and
#            the books keep it in "Pass credits not yet used".
#   use!     a credit becomes that show's tickets, each counting the pass
#            price ÷ credits: the books move that much from the pass into the
#            show's advance sales, and its financials and any split see it.
#            Seats permitting; a season pass is one seat a show.
#   end!     the pass's end date passed: what's left unused is the
#            organization's income, and the held money is theirs to spend.
class TicketPassCredits
  class Error < StandardError; end

  # Nothing is held while they pay, but the price is kept this long.
  BUY_HOLD = 30.minutes
  MAX_PER_ORDER = 10

  def self.start!(pass:, quantity:)
    raise Error, "This pass isn't on sale right now." unless pass.selling_credits?

    quantity = quantity.to_i
    raise Error, "Pick at least one pass." unless quantity.positive?
    raise Error, "You can buy up to #{MAX_PER_ORDER} at a time." if quantity > MAX_PER_ORDER
    if pass.max_sold && quantity > pass.max_sold - pass.holdings.where(status: %w[active ended]).count
      raise Error, "Sorry, there aren't that many passes left."
    end

    ActiveRecord::Base.transaction do
      purchase = TicketPurchase.create!(organization: pass.organization, channel: "online", expires_at: BUY_HOLD.from_now)
      quantity.times do
        holding = purchase.ticket_pass_holdings.create!(organization: pass.organization, ticket_pass: pass, credits: pass.credits,
                                                        credit_value_cents: pass.credit_value_cents, ends_on: pass.ends_on,
                                                        price_cents: pass.price_cents)
        tax = TaxCalculator.for_pass(pass, pass.price_cents)
        tax.lines.each do |line|
          TaxLine.create!(organization_id: pass.organization_id, taxable: holding, tax_rate: line.tax_rate,
                          name: line.name, rate_bps: line.rate_bps, jurisdiction: line.jurisdiction, remitter: line.remitter,
                          included: line.included, exempt: line.exempt, exemption_reason: line.exemption_reason,
                          base_cents: line.base_cents, tax_cents: line.tax_cents, sale_date: Date.current, event_date: pass.ends_on)
        end
        holding.update_columns(tax_cents: tax.tax_cents)
      end
      purchase.price!
    end
  end

  def self.settle!(holding, paid_at:)
    holding.with_lock do
      next unless holding.status == "pending"

      holding.update!(status: "active", paid_at: paid_at)
      TaxLine.where(taxable: holding).update_all(sale_date: paid_at.to_date)
      next unless holding.total_cents.positive?

      organization = holding.organization
      OrgCashEntry.post!(organization: organization, entry_type: "pass_sale", amount_cents: holding.org_net_cents, source: holding,
                         description: "Pass #{holding.ticket_pass.name}", occurred_at: paid_at)
      LedgerPosting.post!(organization: organization, source: holding, kind: "sale", entry_date: paid_at.to_date, cash_date: paid_at.to_date,
                          memo: "Pass #{holding.ticket_pass.name}", lines: [
                            { account: :cocoscout_balance, amount_cents: holding.org_net_cents },
                            { account: :ticketing_fees, amount_cents: holding.platform_fee_cents + holding.processing_cents },
                            { account: :fees_paid_by_buyers, amount_cents: -holding.buyer_fee_cents },
                            { account: :pass_credits_unused, amount_cents: -face_cents(holding) },
                            { account: :tax_to_remit, amount_cents: -holding.tax_cents }
                          ])
    end
  end

  # The pass's price without any tax included in it: what the books owe the
  # holder in shows.
  def self.face_cents(holding)
    holding.price_cents - holding.tax_lines.select(&:included).sum(&:tax_cents)
  end

  # Uses `people` credits on a date (a season pass: always one). by: who did
  # it at the door, where the tickets are checked in at once.
  def self.use!(holding, listing:, people: 1, by: nil, at_door: false)
    raise Error, "This pass can't be used anymore." unless holding.usable?

    people = holding.season? ? 1 : people.to_i
    raise Error, "Pick how many." unless people.positive?
    raise Error, "This pass has #{holding.credits_left} #{holding.credits_left == 1 ? 'credit' : 'credits'} left." if people > holding.credits_left

    coverage = holding.ticket_pass.coverages.find_by(production_id: listing.production_id)
    raise Error, "This pass doesn't cover that show." unless coverage
    raise Error, "That show was canceled." if listing.status == "canceled" || listing.show.canceled
    raise Error, "That show isn't on sale." unless at_door || listing.selling?
    raise Error, "That show is after your pass ends." if listing.show.date_and_time.to_date > holding.ends_on
    if holding.season? && holding.tickets.where(ticket_listing_id: listing.id, status: Ticket::SOLD_STATUSES).exists?
      raise Error, "A season pass is one seat a show, and this one already has its seat."
    end

    tier = coverage.tier_at(listing)
    raise Error, "That show has no tickets to use a credit on." unless tier
    raise Error, "#{tier.name} isn't available for that show." unless tier.available?

    value = holding.credit_value_cents
    order = nil
    ActiveRecord::Base.transaction do
      Ticketing::Inventory.reserve!(listing, { tier => people }) do
        now = Time.current
        price = [ tier.price_cents, value ].max
        order = TicketOrder.create!(organization: holding.organization, ticket_listing: listing, status: "paid",
                                    channel: at_door ? "door_pass" : "pass", money_path: "cocoscout", fee_mode: listing.effective_fee_mode,
                                    paid_at: holding.paid_at || now, buyer_name: holding.holder_name, buyer_email: holding.holder_email,
                                    issued_by: by, subtotal_cents: price * people, discount_cents: (price - value) * people)
        people.times do
          order.tickets.create!(ticket_tier: tier, ticket_listing: listing, ticket_pass_holding: holding,
                                status: at_door ? "checked_in" : "valid", price_cents: price, discount_cents: price - value,
                                checked_in_at: (now if at_door), checked_in_by_id: (by&.id if at_door))
        end
        if (value * people).positive?
          LedgerPosting.post!(organization: holding.organization, source: order, kind: "pass_credit", entry_date: now.to_date,
                              memo: "Pass credit, #{listing.display_title}", lines: [
                                { account: :pass_credits_unused, amount_cents: value * people },
                                { account: :advance_ticket_sales, amount_cents: -value * people, show: listing.show, production: listing.production }
                              ])
        end
      end
    end
    TicketSalesSync.sync!(listing.show)
    order
  rescue Ticketing::Inventory::SoldOut
    raise Error, "Sorry, that show doesn't have the seats left."
  end

  # The dates a holding can use a credit on now: covered, on sale (or about
  # to be), before the pass ends, and (a season pass) not used already.
  def self.usable_listings(holding)
    pass = holding.ticket_pass
    used = holding.season? ? holding.tickets.where(status: Ticket::SOLD_STATUSES).pluck(:ticket_listing_id) : []
    holding.organization.ticket_listings.joins(:show).includes(:production, :ticket_tiers, show: :location)
           .where(production_id: pass.coverages.select(:production_id), status: "on_sale", shows: { canceled: false })
           .where(shows: { date_and_time: Time.current..holding.ends_on.end_of_day })
           .where.not(id: used).order("shows.date_and_time").to_a
           .select { |listing| listing.selling? && pass.coverages.find { |c| c.production_id == listing.production_id }&.tier_at(listing)&.available? }
  end

  # A pass nobody has used yet, refunded in full: what they paid comes back,
  # fees included. Like a ticket refund, CocoScout gives back its 50¢s and the
  # card's processing (which Stripe keeps) comes out of the organization's
  # money. A used pass can't be refunded from here: its tickets were paid for
  # with it.
  def self.refund!(holding, by: nil)
    raise Error, "Only a live pass can be refunded." unless holding.status == "active"
    raise Error, "This pass has been used, so it can't be refunded here." if holding.credits_used.positive?

    organization = holding.organization
    amount = holding.total_cents
    waived = holding.platform_fee_cents
    debit = amount - waived
    intent_id = holding.ticket_purchase&.stripe_payment_intent_id
    OrgCashEntry.with_org_lock(organization) do
      if debit.nonzero?
        OrgCashEntry.post!(organization: organization, entry_type: "pass_refund", amount_cents: -debit, source: holding,
                           description: "Pass refund, #{holding.ticket_pass.name}")
      end
    end
    stripe_refund = if amount.positive? && intent_id.present?
      Stripe::Refund.create({ payment_intent: intent_id, amount: amount, metadata: { ticket_pass_holding_id: holding.id } },
                            { idempotency_key: "pass-refund-#{holding.id}" })
    end

    ActiveRecord::Base.transaction do
      holding.update!(status: "canceled", refunded_cents: amount, refund_org_debit_cents: debit, stripe_refund_id: stripe_refund&.id,
                      refunded_at: Time.current)
      holding.tax_lines.where(reversal_of_id: nil).where("tax_cents >= 0").each do |line|
        TaxLine.create!(line.attributes.except("id", "created_at", "updated_at")
                            .merge("base_cents" => -line.base_cents, "tax_cents" => -line.tax_cents, "sale_date" => Date.current, "reversal_of_id" => line.id))
      end
      if amount.positive?
        LedgerPosting.post!(organization: organization, source: holding, kind: "refund", entry_date: Date.current, cash_date: Date.current,
                            memo: "Pass refund, #{holding.ticket_pass.name}", lines: [
                              { account: :cocoscout_balance, amount_cents: -debit },
                              { account: :pass_credits_unused, amount_cents: face_cents(holding) },
                              { account: :tax_to_remit, amount_cents: holding.tax_cents },
                              { account: :fees_paid_by_buyers, amount_cents: holding.buyer_fee_cents },
                              { account: :ticketing_fees, amount_cents: -waived }
                            ])
      end
    end
    CocoScoutLedgerPoster.post_for!(holding.reload)
    holding
  rescue Stripe::StripeError => e
    OrgCashEntry.unpost!(source: holding, entry_type: "pass_refund")
    raise Error, "Stripe couldn't refund it: #{e.message}"
  end

  def self.end!(holding, at: Time.current)
    holding.with_lock do
      next unless holding.status == "active"

      holding.update!(status: "ended", ended_at: at)
      left = face_cents(holding) - holding.credit_value_cents * holding.credits_used
      next unless left.positive?

      LedgerPosting.post!(organization: holding.organization, source: holding, kind: "pass_end", entry_date: at.to_date,
                          memo: "Unused credits, #{holding.ticket_pass.name}", lines: [
                            { account: :pass_credits_unused, amount_cents: left },
                            { account: :unused_pass_income, amount_cents: -left }
                          ])
    end
  end
end
