# frozen_string_literal: true

# One entry in an organization's catalog of services it can offer on contracts
# (e.g. "Technical services" at $25/hr). Contracts draw from this list and can
# add their own or override the price. Managed on the Contract Settings page.
class ContractServiceOption < ApplicationRecord
  UNITS = %w[flat hourly].freeze
  DIRECTIONS = %w[incoming outgoing].freeze
  # "once" bills a single line for the contract; "per_event" lets the wizard
  # pick which booked dates want the service and set hours per date.
  BOOKING_MODES = %w[once per_event].freeze

  belongs_to :organization

  validates :name, presence: true
  validates :default_price_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :unit, inclusion: { in: UNITS }
  validates :default_direction, inclusion: { in: DIRECTIONS }
  validates :booking_mode, inclusion: { in: BOOKING_MODES }

  scope :ordered, -> { order(:position, :name) }

  def per_event?
    booking_mode == "per_event"
  end

  def default_price
    default_price_cents.to_i / 100.0
  end
end
