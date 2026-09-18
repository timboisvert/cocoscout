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
  # On a shift spanning several shows an extra role may name the shows it covers
  # (see ShiftAdditionalRole), so one role can have a row per show — distinct
  # keeps it listed once.
  has_many :shift_additional_roles, dependent: :destroy
  has_many :additional_roles, -> { distinct }, through: :shift_additional_roles, source: :house_role

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

  # The extra roles that apply to one covered show: those covering every show
  # plus those scoped to this one. Reads the loaded rows, so a preloaded week
  # costs nothing more.
  def additional_roles_for(show)
    shift_additional_roles.select { |r| r.show_id.nil? || r.show_id == show.id }
                          .map(&:house_role).uniq
  end

  # { house_role_id => [show_id, ...] } — an empty list means every show. What
  # the edit modal needs to redraw the current choice.
  def additional_role_scopes
    shift_additional_roles.group_by(&:house_role_id).transform_values do |rows|
      rows.any?(&:all_shows?) ? [] : rows.map(&:show_id).sort
    end
  end

  # Replace the "also covers" set. role_ids are the roles to keep; for any role
  # the caller scoped, show_ids_by_role[role_id] lists the covered shows it
  # applies to. Absent, or naming every covered show, means every show — stored
  # as the single unscoped row so the old meaning is untouched. Present but
  # empty means the scoping was offered and nothing was picked, so the role
  # comes off.
  def assign_additional_roles!(role_ids, show_ids_by_role = {})
    covered_ids = covered_shows.map(&:id)
    ids = Array(role_ids).map(&:to_i).uniq - [ house_role_id ]

    transaction do
      shift_additional_roles.destroy_all
      ids.each do |role_id|
        if show_ids_by_role.key?(role_id)
          chosen = Array(show_ids_by_role[role_id]).map(&:to_i).uniq & covered_ids
          next if chosen.empty?

          if chosen.sort == covered_ids.sort
            shift_additional_roles.create!(house_role_id: role_id)
          else
            chosen.each { |show_id| shift_additional_roles.create!(house_role_id: role_id, show_id: show_id) }
          end
        else
          shift_additional_roles.create!(house_role_id: role_id)
        end
      end
    end
    shift_additional_roles.reset
    additional_roles.reset
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

  # The assignments actually staffing this shift. Someone who said "I can't make
  # it" keeps their row — the manager has to see who dropped and why — but their
  # slot is open again, so every count below ignores them. Rejected in Ruby
  # rather than scoped in SQL so a preloaded week costs no extra queries.
  def active_assignments
    shift_assignments.reject(&:declined?)
  end

  def assigned_count
    active_assignments.size
  end

  def remaining_slots
    [ required_count - assigned_count, 0 ].max
  end

  def fully_staffed?
    return true unless needs_assignment?
    assigned_count >= required_count
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
