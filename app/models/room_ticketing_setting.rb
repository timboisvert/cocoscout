# frozen_string_literal: true

# Ticketing's side of a room (advanced ticketing plan §0): how tickets in it
# are sold (general admission by count, reserved seats, or mixed: standing
# areas by count and seated sections by seat), the chart that draws it, and
# directions for buyers. The room itself (LocationSpace) knows nothing of
# this: rooms are on every plan, ticketing is Pro, and the dependency runs one
# way. Made lazily, like TicketingProfile.for.
class RoomTicketingSetting < ApplicationRecord
  SEATING_MODES = %w[general reserved mixed].freeze
  SEATING_MODE_LABELS = { "general" => "General admission", "reserved" => "Reserved seats", "mixed" => "Mixed: seats and standing" }.freeze

  belongs_to :organization
  belongs_to :location_space
  belongs_to :default_seat_chart, class_name: "SeatChart", optional: true

  validates :seating_mode, inclusion: { in: SEATING_MODES }
  validates :buyer_directions, length: { maximum: 500 }
  validate :chart_is_this_rooms

  def self.for(room)
    find_by(location_space: room) || create!(organization: room.location.organization, location_space: room)
  rescue ActiveRecord::RecordNotUnique
    find_by!(location_space: room)
  end

  def seating_mode_label = SEATING_MODE_LABELS.fetch(seating_mode)
  def seated? = seating_mode != "general"

  # Seat charts arrive with step 4a of the plan; until then there are none.
  def self.seating_built?
    Object.const_defined?(:SeatChart)
  end

  # The room's charts, when seating has been built (step 4a).
  def charts
    return [] unless self.class.seating_built?

    SeatChart.where(location_space_id: location_space_id).order(:name)
  end

  private

  def chart_is_this_rooms
    return if default_seat_chart_id.nil? || !self.class.seating_built? || default_seat_chart.nil?

    errors.add(:default_seat_chart, "is drawn for another room") unless default_seat_chart.location_space_id == location_space_id
  end
end
