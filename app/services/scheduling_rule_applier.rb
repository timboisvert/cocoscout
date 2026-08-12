# frozen_string_literal: true

# Turns approved regulars matches into real shifts and assignments. Takes the
# match keys the manager checked in the Apply-regulars modal, re-runs the
# matcher fresh (so stale keys, since-canceled shows, or availability changes
# between render and submit fall away safely), and creates what's still valid
# inside one transaction.
#
# Slot reuse rules:
#   - a match that found an existing shift assigns onto it, never duplicates it
#   - two approved rules for the same new slot share one created shift
#   - a create that still collides with idx_shifts_no_dupe (racing manager)
#     falls back to assigning onto the shift that beat it there
class SchedulingRuleApplier
  Result = Struct.new(:shifts_created, :people_assigned, :skipped, keyword_init: true)

  def initialize(organization:, week_start:, match_keys:)
    @organization = organization
    @week_start = week_start
    @match_keys = Array(match_keys)
  end

  def apply!
    matcher = SchedulingRuleMatcher.new(organization: @organization, week_start: @week_start)
    selected = matcher.find(@match_keys)
    approved, rejected = selected.partition(&:selectable?)

    assigned = 0
    slot_shifts = {} # slot tuple → shift, so same-slot rules share one record

    ActiveRecord::Base.transaction do
      approved.each do |match|
        shift = match.existing_shift ||
                slot_shifts[slot_key(match)] ||
                create_shift(match)
        slot_shifts[slot_key(match)] = shift
        assigned += 1 if assign(match.person, shift)
      end
    end

    created = slot_shifts.values.uniq.count(&:previously_new_record?)
    Result.new(shifts_created: created, people_assigned: assigned, skipped: rejected.size)
  end

  private

  def slot_key(match)
    [ match.house_role.id, match.starts_at, match.ends_at, match.show&.id ]
  end

  def create_shift(match)
    @organization.shifts.create!(
      house_role: match.house_role,
      source: match.show,
      starts_at: match.starts_at,
      ends_at: match.ends_at,
      required_count: match.house_role.default_required_count
    )
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    # The dedupe index/validation says this exact slot now exists — someone
    # made it between render and submit. Use theirs; anything else re-raises.
    existing = @organization.shifts.find_by(
      house_role_id: match.house_role.id,
      source_type: match.show ? "Show" : nil, source_id: match.show&.id,
      starts_at: match.starts_at, ends_at: match.ends_at
    )
    raise e unless existing

    existing
  end

  def assign(person, shift)
    return false if shift.shift_assignments.reload.any? { |a| a.person_id == person.id }

    next_position = (shift.shift_assignments.map(&:position).max || 0) + 1
    shift.shift_assignments.create!(person: person, position: next_position)
    true
  end
end
