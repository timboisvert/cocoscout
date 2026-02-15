# frozen_string_literal: true

class TicketOffer < ApplicationRecord
  belongs_to :ticket_listing
  belongs_to :show_ticket_tier

  has_many :ticket_sales, dependent: :restrict_with_error

  enum :status, {
    active: "active",
    paused: "paused",
    sold_out: "sold_out",
    hidden: "hidden"
  }, default: :active, prefix: true

  validates :name, presence: true
  validates :quantity, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :seats_per_offer, presence: true, numericality: { greater_than: 0 }
  validates :price_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { status_active }
  scope :available, -> { where("quantity > sold") }

  def price
    price_cents / 100.0
  end

  def price=(value)
    self.price_cents = (value.to_f * 100).round
  end

  def remaining
    quantity - sold
  end

  def sold_out?
    remaining <= 0
  end

  # Total seats this offer represents
  def total_seats_available
    remaining * seats_per_offer
  end

  # Check if this is a bundle (multi-seat offer)
  def bundle?
    seats_per_offer > 1
  end

  # Display name with quantity info
  def display_name
    if bundle?
      "#{name} (#{seats_per_offer} seats)"
    else
      name
    end
  end

  # Record a purchase
  def record_purchase!(quantity_purchased)
    with_lock do
      raise "Not enough offers available" if remaining < quantity_purchased

      self.sold += quantity_purchased
      self.status = :sold_out if sold_out?
      save!
    end
  end
end
