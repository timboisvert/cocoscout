# frozen_string_literal: true

# One checkout and its one payment, holding one order per show. A plain ticket
# purchase has a single order; a pass or a deal on another show adds more.
# Every order keeps its own show, tickets and money (TicketOrderSettlement
# settles each); the purchase holds the clock, the totals and the
# PaymentIntent, and its first order also carries the payment's ids so
# everything that finds an order by its payment still does.
#
# Card processing is charged once for the whole purchase and shared back onto
# its orders in proportion to their money (price!), so the orders always add
# up to the charge and each show's balance gets exactly its own.
class TicketPurchase < ApplicationRecord
  STATUSES = %w[pending paid expired canceled].freeze

  belongs_to :organization
  # A checkout opened from an earlier purchase's deal (TicketOffer).
  belongs_to :earned_by_purchase, class_name: "TicketPurchase", optional: true
  has_many :ticket_orders, -> { order(:id) }, inverse_of: :ticket_purchase, dependent: :nullify
  # Credit passes bought in it (no show yet: credits used later).
  has_many :ticket_pass_holdings, -> { order(:id) }, dependent: :nullify

  validates :status, inclusion: { in: STATUSES }

  before_validation { self.token ||= SecureRandom.urlsafe_base64(24) }

  scope :stale, ->(at = Time.current) { where(status: "pending").where("ticket_purchases.expires_at <= ?", at) }

  # The order the checkout page is opened by (its token is the checkout's
  # address), and the one that carries the payment's ids.
  def primary_order
    ticket_orders.first
  end

  def pending?
    status == "pending"
  end

  def paid?
    status == "paid"
  end

  def hold_expired?(at = Time.current)
    pending? && expires_at.present? && expires_at <= at
  end

  # The purchase's numbers, from every order's tickets and products: one
  # TicketPricing quote (our 50¢ per ticket, processing once), then each
  # order's share of processing in proportion to its money. When buyers pay
  # the fees, each order's buyer-paid fee is its own 50¢s plus its share of
  # processing, so every show nets exactly its tickets.
  def price!
    orders = ticket_orders.includes(tickets: :tax_lines, ticket_order_items: :tax_lines).to_a
    holdings = ticket_pass_holdings.includes(:tax_lines, :ticket_pass).to_a
    fee_mode = orders.first&.fee_mode || holdings.first&.ticket_pass&.fee_mode([]) || "buyer"
    parts = orders.map { |order| TicketCheckout.order_items(order) } + holdings.map { |holding| self.class.holding_items(holding) }
    quote = TicketPricing.quote(items: parts.flatten, fee_mode: fee_mode)
    own = parts.map { |items| TicketPricing.quote(items: items, fee_mode: fee_mode) }
    bases = own.map { |q| q.subtotal_cents - q.discount_cents + q.tax_cents }
    processing = TicketPricing.share(quote.processing_cents, bases)
    buyer_fees = Array.new(orders.size, 0)
    if quote.buyer_fee_cents.positive?
      buyer_fees = own.each_with_index.map { |q, index| q.platform_fee_cents + processing[index] }
      # Rounding Stripe's fee can leave a cent over; it lands on the first show.
      buyer_fees[0] += quote.buyer_fee_cents - buyer_fees.sum
    end

    transaction do
      orders.each_with_index do |order, index|
        total = bases[index] + buyer_fees[index]
        order.update!(subtotal_cents: own[index].subtotal_cents, discount_cents: own[index].discount_cents,
                      tax_cents: order.tickets.sum(&:tax_cents) + order.ticket_order_items.sum(&:tax_cents),
                      platform_fee_cents: own[index].platform_fee_cents, processing_cents: processing[index],
                      buyer_fee_cents: buyer_fees[index], total_cents: total,
                      org_net_cents: total - processing[index] - own[index].platform_fee_cents)
      end
      holdings.each_with_index do |holding, offset|
        index = orders.size + offset
        total = bases[index] + buyer_fees[index]
        holding.update!(platform_fee_cents: own[index].platform_fee_cents, processing_cents: processing[index],
                        buyer_fee_cents: buyer_fees[index], total_cents: total,
                        org_net_cents: total - processing[index] - own[index].platform_fee_cents)
      end
      lines = orders + holdings
      update!(subtotal_cents: orders.sum(&:subtotal_cents) + holdings.sum(&:price_cents), discount_cents: orders.sum(&:discount_cents),
              tax_cents: orders.sum(&:tax_cents) + holdings.sum(&:tax_cents), platform_fee_cents: lines.sum(&:platform_fee_cents),
              processing_cents: lines.sum(&:processing_cents), buyer_fee_cents: lines.sum(&:buyer_fee_cents),
              total_cents: lines.sum(&:total_cents), org_net_cents: lines.sum(&:org_net_cents))
    end
    self
  end

  # A credit pass as TicketPricing items: one per credit (our 50¢ is per
  # admission), sharing the price and the tax added on top.
  def self.holding_items(holding)
    added = holding.tax_lines.reject(&:included).sum(&:tax_cents)
    prices = TicketPricing.share(holding.price_cents, Array.new(holding.credits, 1))
    taxes = TicketPricing.share(added, Array.new(holding.credits, 1))
    prices.zip(taxes).map { |price, tax| { price_cents: price, discount_cents: 0, tax_cents: tax } }
  end

  # Ends a hold: this purchase and every order in it.
  def expire!(at = Time.current)
    transaction do
      update!(status: "expired", expires_at: at)
      ticket_orders.where(status: "pending").update_all(status: "expired", expires_at: at, updated_at: at)
    end
  end
end
