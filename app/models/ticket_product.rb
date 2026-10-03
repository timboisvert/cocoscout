# frozen_string_literal: true

# Something a theater sells alongside tickets — a bottle of champagne for the
# table, a program — defined once for the organization with a standard price.
# A production picks which ones to upsell at its checkout and can set its own
# prices (ProductionTicketingProduct); a sale becomes a TicketOrderItem.
#
# counts_toward_ticket_revenue: whether its sales join the show's ticket
# revenue, which a contract's revenue share is computed on. Off by default,
# so a split never sees bottle money unless the theater wants it to.
class TicketProduct < ApplicationRecord
  belongs_to :organization

  has_many :production_ticketing_products, dependent: :destroy
  has_many :ticket_order_items, dependent: :restrict_with_exception

  validates :name, presence: true, length: { maximum: 80 }
  validates :description, length: { maximum: 200 }
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :active, -> { where(archived_at: nil) }
  scope :ordered, -> { order(:position, :id) }

  # Gone from every production's upsell list. Deleted outright when nobody
  # ever bought one, archived (so orders keep their product) when they did.
  def retire!
    if ticket_order_items.exists?
      transaction do
        production_ticketing_products.delete_all
        update!(archived_at: Time.current)
      end
    else
      destroy!
    end
  end

  def sold_count
    ticket_order_items.where(status: TicketOrderItem::SOLD_STATUSES).sum(:quantity)
  end
end
