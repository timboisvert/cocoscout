# frozen_string_literal: true

# A standing staffing rule — a "regular". Says that a person always works a
# particular slot, in one of two shapes:
#
#   production_anchored — they work every event of one production, in one role
#                         ("Haley always techs Starlet's Burlesque").
#   weekday             — they work the same weekday window every week
#                         ("Camille tends bar Thursdays 6–10pm").
#
# Rules don't create anything by themselves. Each week the manager reviews the
# matches on Scheduling (SchedulingRules::WeekMatcher) and confirms which to
# apply (SchedulingRules::Applier). Branded "Regulars" in the UI only.
class SchedulingRule < ApplicationRecord
  belongs_to :organization
  belongs_to :person
  belongs_to :house_role
  belongs_to :production, optional: true

  # Key is production_anchored (not `production`) to avoid clashing with the
  # association name.
  enum :rule_type, { production_anchored: 0, weekday: 1 }, default: :production_anchored

  scope :active, -> { where(archived_at: nil) }

  validates :production, presence: true, if: :production_anchored?
  validates :day_of_week, inclusion: { in: 0..6 }, if: :weekday?
  validates :starts_local_time, :ends_local_time, presence: true, if: :weekday?
  validate :records_belong_to_organization
  validate :no_duplicate_active_rule

  DAY_NAMES = Date::DAYNAMES.freeze

  # Human description of what the rule targets: the production's name, or
  # "Thursdays 6:00 PM – 10:00 PM". Times are raw `time` columns — format them
  # directly, never through Time.zone.
  def target_label
    if production_anchored?
      production&.name.to_s
    else
      "#{DAY_NAMES[day_of_week].pluralize} #{time_window_label}"
    end
  end

  def time_window_label
    return "" if starts_local_time.blank? || ends_local_time.blank?

    "#{format_local_time(starts_local_time)} – #{format_local_time(ends_local_time)}"
  end

  private

  def format_local_time(t)
    t.strftime("%-l:%M %p")
  end

  # Everything a rule points at must live in the rule's own org. The person must
  # additionally be on staff (an active OrganizationStaffMember) when the rule
  # is created — a rule for a non-staffer could never produce a usable match.
  def records_belong_to_organization
    return if organization.blank?

    if house_role && house_role.organization_id != organization_id
      errors.add(:house_role, "must belong to this organization")
    end
    if production_anchored? && production && production.organization_id != organization_id
      errors.add(:production, "must belong to this organization")
    end
    if person && !OrganizationStaffMember.active.exists?(organization_id: organization_id, person_id: person_id)
      errors.add(:person, "must be an active staff member of this organization")
    end
  end

  # One active rule per person/role/target. Model-level only: the tuple has
  # NULLs on both branches, so a partial unique index can't express it.
  def no_duplicate_active_rule
    return if archived_at.present? || person_id.blank?

    dupes = SchedulingRule.active.where(
      organization_id: organization_id,
      person_id: person_id,
      house_role_id: house_role_id,
      rule_type: rule_type,
      production_id: production_id,
      day_of_week: day_of_week
    )
    dupes = dupes.where.not(id: id) if persisted?
    errors.add(:base, "There's already a rule like this for #{person&.name || 'this person'}.") if dupes.exists?
  end
end
