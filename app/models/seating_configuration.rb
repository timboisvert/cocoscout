# frozen_string_literal: true

class SeatingConfiguration < ApplicationRecord
  belongs_to :organization
  belongs_to :location, optional: true
  belongs_to :location_space, optional: true

  has_many :seating_zones, -> { order(:position) }, dependent: :destroy
  has_many :ticket_tiers, -> { order(:position) }, dependent: :destroy
  has_many :show_ticketings, dependent: :nullify

  enum :status, {
    active: "active",
    archived: "archived"
  }, default: :active, prefix: true

  validates :name, presence: true

  scope :active, -> { status_active }
  scope :ordered, -> { order(:name) }

  accepts_nested_attributes_for :ticket_tiers, allow_destroy: true
  accepts_nested_attributes_for :seating_zones, allow_destroy: true

  def total_capacity
    if seating_zones.any?
      seating_zones.sum(:total_capacity)
    else
      ticket_tiers.sum(:capacity)
    end
  end

  def display_name
    if location_space.present?
      "#{location_space.display_name} - #{name}"
    else
      name
    end
  end

  # Duplicate this configuration with all tiers for a new show
  def duplicate_tiers_for(show_ticketing)
    ticket_tiers.each do |tier|
      show_ticketing.show_ticket_tiers.create!(
        ticket_tier: tier,
        name: tier.name,
        capacity: tier.capacity,
        available: tier.capacity,
        default_price_cents: tier.default_price_cents,
        position: tier.position
      )
    end
  end
end
