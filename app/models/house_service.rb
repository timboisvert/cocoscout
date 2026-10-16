# frozen_string_literal: true

# One thing the organization offers its productions (after-V1 #6, Tim
# 2026-10-16): booth tech, ticket taking, a videographer, a projector. Defined
# once in Organization settings → Services, beside Locations, with a default
# price and the roles that do it: several (ticket taking: Front of House or
# House Manager) or none (equipment, a fee). Not every role is a service, and a
# service points at its roles, never the reverse.
#
# Our own productions pick from this list (ProductionServiceNeed), a show can
# differ (ShowServiceChange), and Contract Settings chooses which ones
# contracts offer and on what terms (the contract_* columns). Role Call checks
# that every show has someone on each service it needs (ShowServices).
class HouseService < ApplicationRecord
  UNITS = %w[flat hourly].freeze
  DIRECTIONS = %w[incoming outgoing].freeze
  # "once" bills one line for the contract; "per_event" lets a contract pick
  # which of its booked dates get the service.
  BOOKING_MODES = %w[once per_event].freeze

  belongs_to :organization
  has_many :house_service_roles, dependent: :destroy
  has_many :house_roles, through: :house_service_roles
  has_many :production_service_needs, dependent: :destroy
  has_many :show_service_changes, dependent: :destroy

  validates :name, presence: true, length: { maximum: 100 },
                   uniqueness: { scope: :organization_id, case_sensitive: false }
  validates :default_price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :contract_price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :unit, inclusion: { in: UNITS }
  validates :contract_direction, inclusion: { in: DIRECTIONS }
  validates :contract_booking_mode, inclusion: { in: BOOKING_MODES }

  scope :ordered, -> { order(:position, :name) }
  scope :offered_on_contracts, -> { where(offered_on_contracts: true) }

  def hourly?
    unit == "hourly"
  end

  # "$25.00/hr" or "$40.00 flat".
  def price_label(cents = default_price_cents)
    "$#{format('%.2f', cents.to_i / 100.0)}#{hourly? ? '/hr' : ' flat'}"
  end

  def default_price
    default_price_cents.to_i / 100.0
  end

  # What a contract charges unless it says otherwise: Contract Settings' price
  # for it, else the default price.
  def contract_price_cents_or_default
    contract_price_cents || default_price_cents
  end

  def contract_price
    contract_price_cents_or_default / 100.0
  end

  def contract_per_event?
    contract_booking_mode == "per_event"
  end

  # Whether anyone on staff does it: a service with no roles is equipment or a
  # fee, billed on contracts but never staffed or checked by Role Call.
  def staffed?
    house_roles.any?
  end

  # "Front of House or House Manager".
  def roles_label
    house_roles.map(&:name).to_sentence(two_words_connector: " or ", last_word_connector: ", or ")
  end

  # Dollars from a form ("25", "$25.00") to cents; blank → nil.
  def self.cents_from(value)
    return nil if value.blank?

    (value.to_s.delete("$,").to_d * 100).round
  end
end
