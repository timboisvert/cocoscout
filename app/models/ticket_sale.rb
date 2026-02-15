# frozen_string_literal: true

class TicketSale < ApplicationRecord
  belongs_to :ticket_offer
  belongs_to :show_ticket_tier

  enum :status, {
    confirmed: "confirmed",
    refunded: "refunded",
    cancelled: "cancelled"
  }, default: :confirmed, prefix: true

  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :total_seats, presence: true, numericality: { greater_than: 0 }
  validates :total_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :purchased_at, presence: true
  validates :external_sale_id, uniqueness: { scope: :ticket_offer_id }, allow_blank: true

  scope :confirmed, -> { status_confirmed }
  scope :recent, -> { order(purchased_at: :desc) }
  scope :today, -> { where(purchased_at: Time.current.beginning_of_day..Time.current.end_of_day) }

  def total
    total_cents / 100.0
  end

  def total=(value)
    self.total_cents = (value.to_f * 100).round
  end

  # Process a refund
  def refund!
    return unless status_confirmed?

    transaction do
      show_ticket_tier.record_refund!(total_seats)
      ticket_offer.with_lock do
        ticket_offer.sold -= quantity
        ticket_offer.status = :active if ticket_offer.status_sold_out?
        ticket_offer.save!
      end
      update!(status: :refunded)
    end
  end

  # Display info
  def display_info
    "#{quantity}x #{ticket_offer.name} (#{total_seats} seats)"
  end

  # Provider name
  def provider_name
    ticket_offer.ticket_listing.ticketing_provider.name
  end
end
