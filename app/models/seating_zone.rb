# frozen_string_literal: true

class SeatingZone < ApplicationRecord
  belongs_to :seating_configuration

  has_many :ticket_tiers, dependent: :nullify

  ZONE_TYPES = {
    individual_seats: "individual_seats",
    tables: "tables",
    rows: "rows",
    booths: "booths",
    standing: "standing"
  }.freeze

  enum :zone_type, ZONE_TYPES, prefix: true

  validates :name, presence: true
  validates :zone_type, presence: true
  validates :unit_count, presence: true, numericality: { greater_than: 0 }
  validates :capacity_per_unit, presence: true, numericality: { greater_than: 0 }
  validates :total_capacity, presence: true, numericality: { greater_than: 0 }
  validates :position, presence: true, numericality: { greater_than_or_equal_to: 0 }

  before_validation :calculate_total_capacity
  before_validation :set_position, on: :create

  scope :ordered, -> { order(:position) }

  # Human-readable summary of the zone
  # e.g., "4 tables × 2 chairs (8 total)" or "11 seats" or "Standing room (50 capacity)"
  def formatted_summary
    case zone_type
    when "individual_seats"
      "#{unit_count} #{'seat'.pluralize(unit_count)}"
    when "tables"
      "#{unit_count} #{'table'.pluralize(unit_count)} × #{capacity_per_unit} #{'seat'.pluralize(capacity_per_unit)} (#{total_capacity} total)"
    when "rows"
      "#{unit_count} #{'row'.pluralize(unit_count)} × #{capacity_per_unit} #{'seat'.pluralize(capacity_per_unit)} (#{total_capacity} total)"
    when "booths"
      "#{unit_count} #{'booth'.pluralize(unit_count)} × #{capacity_per_unit} capacity (#{total_capacity} total)"
    when "standing"
      "Standing room (#{total_capacity} capacity)"
    else
      "#{total_capacity} capacity"
    end
  end

  # Human-readable zone type label
  def zone_type_label
    case zone_type
    when "individual_seats"
      "Individual Seats"
    when "tables"
      "Tables"
    when "rows"
      "Rows of Seats"
    when "booths"
      "Booths / Private Areas"
    when "standing"
      "Standing Room"
    else
      zone_type&.titleize
    end
  end

  # Icon name for the zone type (for UI)
  def zone_type_icon
    case zone_type
    when "individual_seats"
      "chair"
    when "tables"
      "table"
    when "rows"
      "rows"
    when "booths"
      "booth"
    when "standing"
      "standing"
    else
      "chair"
    end
  end

  private

  def calculate_total_capacity
    self.total_capacity = (unit_count || 0) * (capacity_per_unit || 0)
  end

  def set_position
    return if position.present?

    max_position = seating_configuration&.seating_zones&.maximum(:position) || -1
    self.position = max_position + 1
  end
end
