# frozen_string_literal: true

# A product a production upsells at checkout, in the order it's offered.
# price_cents and counts_toward_ticket_revenue are this production's own
# answers, read only while the setup's own_product_prices switch is on; nil
# (or the switch off) means the product's standard ones.
class ProductionTicketingProduct < ApplicationRecord
  belongs_to :production_ticketing
  belongs_to :ticket_product

  validates :ticket_product_id, uniqueness: { scope: :production_ticketing_id }
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  # What a buyer of this production pays and how the sale counts.
  def offer
    own = production_ticketing.own_product_prices
    TicketProductOffer.new(
      product: ticket_product,
      price_cents: own && price_cents ? price_cents : ticket_product.price_cents,
      counts_toward_ticket_revenue: own && !counts_toward_ticket_revenue.nil? ? counts_toward_ticket_revenue : ticket_product.counts_toward_ticket_revenue,
      taxable: ticket_product.taxable
    )
  end
end
