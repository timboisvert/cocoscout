# frozen_string_literal: true

class SpaceRental < ApplicationRecord
  belongs_to :contract
  belongs_to :location
  belongs_to :location_space, optional: true

  has_many :shows, dependent: :nullify

  validates :starts_at, presence: true
  validates :ends_at, presence: true
  validate :ends_after_starts
  validate :no_overlapping_rentals, on: :create

  scope :upcoming, -> { where("starts_at >= ?", Time.current).order(:starts_at) }
  scope :past, -> { where("ends_at < ?", Time.current).order(starts_at: :desc) }
  scope :confirmed, -> { where(confirmed: true) }
  scope :for_date_range, ->(start_date, end_date) {
    where("starts_at <= ? AND ends_at >= ?", end_date, start_date)
  }

  # Space name (handles "Entire venue" case)
  def space_name
    location_space&.name || "Entire Venue"
  end

  # Duration in hours
  def duration_hours
    ((ends_at - starts_at) / 1.hour).round(1)
  end

  # Display helpers
  def date_display
    starts_at.strftime("%B %d, %Y")
  end

  def time_range_display
    "#{starts_at.strftime('%l:%M %p')} - #{ends_at.strftime('%l:%M %p')}".strip
  end

  def full_display
    space_display = location_space&.display_name || location.name
    "#{space_display}: #{date_display} #{time_range_display}"
  end

  private

  def ends_after_starts
    return if starts_at.blank? || ends_at.blank?

    if ends_at <= starts_at
      errors.add(:ends_at, "must be after start time")
    end
  end

  def no_overlapping_rentals
    return if starts_at.blank? || ends_at.blank?
    return if location_space_id.blank? # Skip overlap check for entire venue bookings

    overlapping = SpaceRental
      .joins(:contract)
      .where(location_space_id: location_space_id)
      .where.not(id: id)
      .where.not(contracts: { status: "cancelled" })
      .where("space_rentals.starts_at < ? AND space_rentals.ends_at > ?", ends_at, starts_at)

    if overlapping.any?
      # Build detailed error message with specific conflict times
      conflict_details = overlapping.limit(3).map do |rental|
        "#{rental.starts_at.strftime('%b %-d at %-I:%M %p')} - #{rental.ends_at.strftime('%-I:%M %p')}"
      end.join(", ")

      if overlapping.count > 3
        conflict_details += " and #{overlapping.count - 3} more"
      end

      errors.add(:base, "This time slot overlaps with existing rentals: #{conflict_details}")
    end
  end
end
