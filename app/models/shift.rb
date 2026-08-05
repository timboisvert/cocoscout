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

  # Extra shows this shift covers beyond its own `source` — only populated when
  # show-based shifts are deliberately merged. Empty for the normal one-per-show
  # case; covered_shows falls back to `source` then.
  has_many :shift_shows, dependent: :destroy
  has_many :shows, through: :shift_shows

  enum :coverage_mode, {
    needs_assignment: 0,
    covered_by_renter: 1,
    not_needed: 2
  }, default: :needs_assignment

  validates :starts_at, :ends_at, presence: true
  validates :required_count, numericality: { only_integer: true, greater_than: 0 }
  validate :ends_after_starts
  validate :no_duplicate_shift

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

  # Scheduled length in hours (used to prefill a worker's time confirmation).
  def scheduled_hours
    return 0 if starts_at.blank? || ends_at.blank?

    ((ends_at - starts_at) / 1.hour).round(2)
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

  # :day or :evening, used to match against staff unavailability scopes.
  def day_part
    StaffUnavailability.day_part_for(starts_at)
  end

  private

  def ends_after_starts
    return unless starts_at.present? && ends_at.present? && ends_at <= starts_at
    errors.add(:ends_at, "must be after the shift start time")
  end

  public

  # The show(s) this shift is tied to. One show normally (its `source`); several
  # only when show-based shifts have been merged (tracked explicitly, never
  # inferred from time). Ordered by show start.
  def covered_shows
    extra = shows.to_a
    if extra.any?
      ([ source ].select { |s| s.is_a?(::Show) } + extra).uniq.sort_by(&:date_and_time)
    else
      [ source ].select { |s| s.is_a?(::Show) }
    end
  end

  private

  # Mirrors the idx_shifts_no_dupe unique index so a colliding create/edit fails
  # validation (friendly message) instead of raising RecordNotUnique at the DB.
  def no_duplicate_shift
    return if starts_at.blank? || ends_at.blank? || house_role_id.blank?

    dupes = Shift.where(
      house_role_id: house_role_id,
      source_type: source_type, source_id: source_id,
      starts_at: starts_at, ends_at: ends_at
    )
    dupes = dupes.where.not(id: id) if persisted?
    errors.add(:base, "There's already a shift for this role at that time.") if dupes.exists?
  end
end
