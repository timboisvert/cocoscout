# frozen_string_literal: true

class TicketBundleItem < ApplicationRecord
  belongs_to :ticket_bundle
  belongs_to :show_ticket_tier

  validates :quantity, presence: true, numericality: { greater_than: 0 }

  # Total seats this item represents
  def total_seats
    quantity
  end

  # Price for this item at normal rate
  def normal_price_cents
    quantity * show_ticket_tier.default_price_cents
  end

  def normal_price
    normal_price_cents / 100.0
  end

  # Tier name
  def tier_name
    show_ticket_tier.name
  end

  # Display
  def display
    "#{quantity}x #{tier_name}"
  end
end
