# frozen_string_literal: true

# A price on a listing — "General $20, 60 seats" — with an optional seat count
# and sales window. Hidden tiers only show once a buyer enters their unlock
# code. Seats left are always counted by Ticketing::Inventory, never stored.
#
# A tier belongs to one show's listing, or to a production's ticketing setup
# (ProductionTicketing). A show that inherits the production's prices holds
# copies of the production's tiers, each pointing at its source_tier.
class TicketTier < ApplicationRecord
  belongs_to :ticket_listing, inverse_of: :ticket_tiers, optional: true
  belongs_to :production_ticketing, inverse_of: :ticket_tiers, optional: true
  belongs_to :source_tier, class_name: "TicketTier", optional: true
  has_many :tickets, dependent: :restrict_with_error
  has_many :copies, class_name: "TicketTier", foreign_key: :source_tier_id, inverse_of: :source_tier, dependent: :nullify

  normalizes :unlock_code, with: ->(c) { c.to_s.strip.upcase.presence }

  validates :name, presence: true, length: { maximum: 80 }
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :min_per_order, numericality: { only_integer: true, greater_than: 0 }
  validates :max_per_order, numericality: { only_integer: true, greater_than_or_equal_to: :min_per_order }, allow_nil: true
  validates :unlock_code, presence: true, if: :hidden?
  validate :seats_cover_tickets_sold, if: -> { persisted? && quantity_changed? && quantity }
  validate :one_owner

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

  def one_owner
    errors.add(:base, "A ticket type belongs to a show or to a production, not both") if ticket_listing && production_ticketing
    errors.add(:base, "A ticket type needs a show or a production") unless ticket_listing || production_ticketing
  end

  def seats_cover_tickets_sold
    sold = sold_count
    errors.add(:quantity, "can't be fewer than the #{sold} already sold") if quantity < sold
  end
end
