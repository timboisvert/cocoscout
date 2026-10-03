# frozen_string_literal: true

# A product as one production sells it: the product, the price that applies
# there, and whether its sales count as ticket revenue (see
# ProductionTicketingProduct#offer).
TicketProductOffer = Data.define(:product, :price_cents, :counts_toward_ticket_revenue, :taxable) do
  def id = product.id
  def name = product.name
  def description = product.description
  def free? = price_cents.zero?
end
