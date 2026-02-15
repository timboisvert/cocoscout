# frozen_string_literal: true

class TicketBundle < ApplicationRecord
  belongs_to :show_ticketing

  has_many :ticket_bundle_items, dependent: :destroy
  has_many :show_ticket_tiers, through: :ticket_bundle_items

  validates :name, presence: true
  validates :total_seats, presence: true, numericality: { greater_than: 0 }
  validates :bundle_price_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }

  def bundle_price
    bundle_price_cents / 100.0
  end

  def bundle_price=(value)
    self.bundle_price_cents = (value.to_f * 100).round
  end

  # Calculate total normal price of individual seats
  def normal_price_cents
    ticket_bundle_items.includes(:show_ticket_tier).sum do |item|
      item.quantity * item.show_ticket_tier.default_price_cents
    end
  end

  def normal_price
    normal_price_cents / 100.0
  end

  # Discount amount
  def savings_cents
    normal_price_cents - bundle_price_cents
  end

  def savings
    savings_cents / 100.0
  end

  # Discount percentage
  def discount_percentage
    return 0 if normal_price_cents.zero?

    ((savings_cents.to_f / normal_price_cents) * 100).round(1)
  end

  # Check if bundle is available (all tiers have enough seats)
  def available?
    return false unless active?

    ticket_bundle_items.all? do |item|
      item.show_ticket_tier.available >= item.quantity
    end
  end

  # Display name with savings
  def display_name
    if savings_cents.positive?
      "#{name} (Save #{discount_percentage}%)"
    else
      name
    end
  end

  # Purchase bundle
  def purchase!
    return false unless available?

    transaction do
      ticket_bundle_items.each do |item|
        item.show_ticket_tier.record_sale!(item.quantity)
      end
    end
    true
  rescue StandardError
    false
  end
end
