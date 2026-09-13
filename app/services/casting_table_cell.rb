# frozen_string_literal: true

# One cell of a casting table — this member, on this night — worked out well
# enough to decide something with.
#
# The old picker was a flat column of role buttons: on a ten-act lineup that's
# ten near-identical names with no running order, no sign of who else is in the
# show, and no sign of what this person already has. Everything a manager
# compares against was missing. This assembles it: the lineup in order, each
# slot's occupants by name, what this member holds, and whether taking another
# act would collide with something else that night.
#
# Assignments are matched to the show's lineup by Role#match_key (name plus its
# ordinal among same-named siblings), not by name. An act-based lineup may
# legitimately repeat a name — "Magic" in each half — and matching on the name
# alone folded both onto one slot, so one read as over-full and the other empty.
class CastingTableCell
  # A castable slot in the lineup, or an intermission divider (kind == :break).
  Slot = Struct.new(:role, :kind, :number, :filled, :total, :occupants, keyword_init: true) do
    def break? = kind == :break
    def full? = !break? && filled >= total
    def held_by_member? = occupants.any?(&:is_member)
    def open_slots = [ total - filled, 0 ].max
  end

  Occupant = Struct.new(:name, :member, :draft, :is_member, keyword_init: true) do
    def draft? = draft
  end

  def initialize(casting_table:, show:, member:)
    @casting_table = casting_table
    @show = show
    @member = member
  end

  attr_reader :show, :member

  def act_based?
    show.act_based?
  end

  # The running order in act mode (acts and intermissions), or simply every
  # non-standing role in role-based mode.
  def lineup_slots
    slots.reject { |s| s.role.standing? }
  end

  # "Show roles" — the MC, the stage kitten: cast per show, but not acts.
  def standing_slots
    slots.select { |s| s.role.standing? }
  end

  # What this member already holds on this night, in lineup order.
  def member_slots
    slots.select(&:held_by_member?)
  end

  # Everyone in the show tonight, with how many slots each has — the "who else
  # am I comparing against" line.
  def other_occupants
    slots.reject(&:break?).flat_map(&:occupants).reject(&:is_member)
         .group_by(&:name).map { |name, list| [ name, list.size ] }.sort_by(&:first)
  end

  def total_slots
    slots.sum { |s| s.break? ? 0 : s.total }
  end

  def filled_slots
    slots.reject(&:break?).sum(&:filled)
  end

  def fully_cast?
    total_slots.positive? && filled_slots >= total_slots
  end

  # Double-bookings elsewhere that night, and declared unavailability. Members
  # already cast in THIS show are exempt from the overlap check — a second act
  # on the same night is the whole point.
  def conflicts
    @conflicts ||= CastingConflicts.for_member(show: show, assignable: member)
  end

  # Whether a restricted role will take this member. Advisory: the board warns
  # and lets you through, and so does this.
  def eligible_for?(role)
    return true unless role.restricted?

    role.eligible?(member)
  end

  private

  def slots
    @slots ||= build_slots
  end

  def roles
    @roles ||= show.available_roles.order(:position).to_a
  end

  def build_slots
    numbers = Role.lineup_numbers_for(roles)
    by_key = Role.match_keys_for(roles)
    drafts = group_by_slot(@casting_table.casting_table_draft_assignments
                                         .where(show_id: show.id).includes(:assignable, :role), by_key, draft: true)
    live = group_by_slot(ShowPersonRoleAssignment.where(show_id: show.id).includes(:assignable, :role),
                         by_key, draft: false)

    roles.map do |role|
      occupants = (live[role.id].to_a + drafts[role.id].to_a)
      Slot.new(
        role: role,
        kind: role.break? ? :break : :castable,
        number: numbers[role.id],
        filled: occupants.size,
        total: role.total_slots,
        occupants: occupants
      )
    end
  end

  # An assignment may still point at a production-level role while the show has
  # since materialized its own copies, so resolve through the match key and fall
  # back to the raw id.
  def group_by_slot(assignments, by_key, draft:)
    assignments.group_by { |a| resolve_slot_id(a.role, by_key) }
               .transform_values do |list|
      list.map do |a|
        Occupant.new(name: a.assignable&.name || a.try(:guest_name) || "Someone",
                     member: a.assignable, draft: draft,
                     is_member: same_member?(a.assignable))
      end
    end
  end

  def resolve_slot_id(role, by_key)
    return role.id if by_key.value?(role)

    by_key[Role.match_key_for(role, role.siblings.to_a)]&.id || role.id
  end

  def same_member?(assignable)
    assignable.present? && member.present? &&
      assignable.class.name == member.class.name && assignable.id == member.id
  end
end
