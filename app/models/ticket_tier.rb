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
  # A bundle ("4 × General for $70") admits several people of another type,
  # using that type's seats; each ticket it makes is that type's ticket.
  belongs_to :bundle_of, class_name: "TicketTier", foreign_key: :bundle_of_tier_id, optional: true
  has_many :bundles, class_name: "TicketTier", foreign_key: :bundle_of_tier_id, inverse_of: :bundle_of, dependent: :nullify
  # The tickets a bundle made (they belong to its type, remembering the bundle).
  has_many :bundle_tickets, class_name: "Ticket", foreign_key: :bundle_tier_id, inverse_of: :bundle_tier, dependent: :restrict_with_error

  normalizes :unlock_code, with: ->(c) { c.to_s.strip.upcase.presence }

  validates :name, presence: true, length: { maximum: 80 }
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  # People one purchase admits: 1 for a ticket; 2 to 20 for a bundle.
  validates :admits, numericality: { only_integer: true, in: 1..20 }
  validates :admits, numericality: { greater_than: 1, message: "must be at least 2 for a bundle" }, if: :bundle?
  validate :bundles_a_plain_type_of_its_own
  # A plain ticket admits one; a bundle has no seats of its own (it uses its
  # type's).
  before_validation { bundle? ? self.quantity = nil : self.admits = 1 }
  validates :min_per_order, numericality: { only_integer: true, greater_than: 0 }
  validates :max_per_order, numericality: { only_integer: true, greater_than_or_equal_to: :min_per_order }, allow_nil: true
  validates :unlock_code, presence: true, if: :hidden?
  validate :seats_cover_tickets_sold, if: -> { persisted? && quantity_changed? && quantity }
  validate :one_owner

  scope :active, -> { where(archived_at: nil) }

  # A ticket type that admits several people of another type for one price.
  def bundle?
    bundle_of_tier_id.present?
  end

  # The type whose tickets (and seats) a purchase of this one uses.
  def base_tier
    bundle? ? bundle_of : self
  end

  # "4 × General"
  def bundle_label
    "#{admits} × #{bundle_of&.name}" if bundle?
  end

  # One purchase's price split into one ticket per person: $70 for 4 is
  # [1750, 1750, 1750, 1750]; any odd cents go to the first tickets, so they
  # always add up to the price.
  def seat_prices(cents = price_cents)
    self.class.split(cents, admits.to_i.clamp(1, 20))
  end

  def self.split(cents, parts)
    base, extra = cents.to_i.divmod(parts)
    Array.new(parts) { |i| base + (i < extra ? 1 : 0) }
  end

  # How many of this type's purchases fit in `seats` seats.
  def units_for(seats)
    seats.nil? ? nil : seats / admits.to_i.clamp(1, 20)
  end

  def free?
    price_cents.zero?
  end

  # People sold on it (a bundle: people its purchases admitted).
  def sold_count
    (bundle? ? bundle_tickets : tickets).where(status: Ticket::SOLD_STATUSES).count
  end

  # A type the show no longer sells: deleted outright when no ticket was ever
  # bought on it, archived (so those tickets keep their type) when one was.
  def retire!
    if tickets.exists? || bundle_tickets.exists?
      update_columns(archived_at: Time.current, updated_at: Time.current) if archived_at.nil?
    else
      destroy!
    end
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

  def bundles_a_plain_type_of_its_own
    return unless bundle?

    base = bundle_of
    same_home = base && base.ticket_listing_id == ticket_listing_id && base.production_ticketing_id == production_ticketing_id
    errors.add(:bundle_of_tier_id, "must be one of this show's ticket types") unless same_home && !base.bundle? && base.id != id
  end
end
