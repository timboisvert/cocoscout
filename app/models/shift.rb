# frozen_string_literal: true

# A single staffing block for a house role at a specific time.
# source is polymorphic: usually a Show (per-show shift generation), sometimes
# a SpaceRental (third-party event), or NULL for free-standing shifts (e.g.
# "bartender on for the evening" not tied to a single show).
class Shift < ApplicationRecord
  belongs_to :organization
  belongs_to :house_role
  belongs_to :source, polymorphic: true, optional: true

  # Extra roles this one shift also covers ("doubling up"), e.g. a bartender who
  # is also the manager and house staff. One shift, one assignment, many duties.
  has_many :shift_additional_roles, dependent: :destroy
  has_many :additional_roles, through: :shift_additional_roles, source: :house_role

  has_many :shift_assignments, dependent: :destroy
  has_many :assigned_people, through: :shift_assignments, source: :person

  enum :coverage_mode, {
    needs_assignment: 0,
    covered_by_renter: 1,
    not_needed: 2
  }, default: :needs_assignment

  validates :starts_at, :ends_at, presence: true
  validates :required_count, numericality: { only_integer: true, greater_than: 0 }
  validate :ends_after_starts

  # True when this shift covers more than one role.
  def doubled?
    additional_roles.any?
  end

  # Names of every role this shift covers, primary first.
  def all_role_names
    [ house_role.name ] + additional_roles.map(&:name)
  end

  # Display label combining all roles, e.g. "Bartender + Manager + Security".
  def role_label
    all_role_names.join(" + ")
  end

  scope :for_week, ->(date) {
    week_start = date.beginning_of_week
    week_end = date.end_of_week
    where("starts_at >= ? AND starts_at <= ?", week_start.beginning_of_day, week_end.end_of_day)
  }

  scope :ordered, -> { order(:starts_at, :id) }

  # Slot-fill status helpers used in the scheduling UI.
  def assigned_count
    shift_assignments.size
  end

  def remaining_slots
    [ required_count - assigned_count, 0 ].max
  end

  def fully_staffed?
    return true unless needs_assignment?
    assigned_count >= required_count
  end

  # Acknowledgement applies only to the specific gap whose next-start matches
  # the stored timestamp. If the next shift moves, the acknowledgement becomes
  # stale on its own — no manual cleanup needed.
  def gap_after_acknowledged?(next_starts_at)
    gap_after_acknowledged_until.present? && gap_after_acknowledged_until == next_starts_at
  end

  # :day or :evening, used to match against staff unavailability scopes.
  def day_part
    StaffUnavailability.day_part_for(starts_at)
  end

  private

  def ends_after_starts
    return unless starts_at.present? && ends_at.present? && ends_at <= starts_at
    errors.add(:ends_at, "must be after the shift start time")
  end
end
