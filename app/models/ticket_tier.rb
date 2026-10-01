# frozen_string_literal: true

# A price on a listing — "General $20, 60 seats" — with an optional seat count
# and sales window. Hidden tiers only show once a buyer enters their unlock
# code. Seats left are always counted by Ticketing::Inventory, never stored.
class TicketTier < ApplicationRecord
  belongs_to :ticket_listing, inverse_of: :ticket_tiers
  has_many :tickets, dependent: :restrict_with_error

  normalizes :unlock_code, with: ->(c) { c.to_s.strip.upcase.presence }

  validates :name, presence: true, length: { maximum: 80 }
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :min_per_order, numericality: { only_integer: true, greater_than: 0 }
  validates :max_per_order, numericality: { only_integer: true, greater_than_or_equal_to: :min_per_order }, allow_nil: true
  validates :unlock_code, presence: true, if: :hidden?
  validate :seats_cover_tickets_sold, if: -> { persisted? && quantity_changed? && quantity }

  scope :active, -> { where(archived_at: nil) }

  def free?
    price_cents.zero?
  end

  def sold_count
    tickets.where(status: Ticket::SOLD_STATUSES).count
  end

  def selling?(at = Time.current)
    archived_at.nil? &&
      (sales_start_at.nil? || sales_start_at <= at) &&
      (sales_end_at.nil? || at < sales_end_at)
  end

  private

  def seats_cover_tickets_sold
    sold = sold_count
    errors.add(:quantity, "can't be fewer than the #{sold} already sold") if quantity < sold
  end
end
