# frozen_string_literal: true

# Reshapes a role-based lineup into an act-based one without losing anything.
#
# A role-based production fills named positions ("Dancer ×5"); an act-based one
# is a running order where every Role is one act with one slot. Flipping the
# mode is presentational — but a role holding five people would then read as
# ONE act with five slots, which is the wrong shape for a lineup. So when a
# production (or one show's override) switches to acts, every castable role
# with more than one slot is split: the original role stays as the first act
# (quantity 1, same id, same position), and quantity-1 new roles are created
# right after it in the running order — same name, category, restriction and
# eligibilities. Each cast assignment in slot k moves to the k-th act, its
# cast notification and any vacancy it left move with it, so nobody reads as
# newly cast or removed. Rename the acts in the Lineup afterwards.
#
# Idempotent: a lineup that's already all single-slot acts is left untouched.
# Breaks and quantity-1 roles are never touched. Draft casting-table
# assignments stay on the original role.
#
# The reverse (acts → roles) needs no conversion: acts are already
# single-slot roles, so nothing is lost by simply flipping the mode.
class CastingModeConverter
  Summary = Struct.new(:roles_split, :acts_created, :assignments_moved,
                       :notifications_moved, :vacancies_moved, :lineups_copied,
                       keyword_init: true) do
    def initialize(**)
      super
      self.roles_split ||= 0
      self.acts_created ||= 0
      self.assignments_moved ||= 0
      self.notifications_moved ||= 0
      self.vacancies_moved ||= 0
      self.lineups_copied ||= 0
    end

    def changed?
      roles_split.positive? || lineups_copied.positive?
    end

    def merge!(other)
      each_pair { |k, v| self[k] = v + other[k] }
      self
    end
  end

  # The production has just switched to acts. Split its own lineup (which
  # every show that inherits it casts from), then the custom lineup of each
  # show that inherits the production's mode — those flipped with it. Shows
  # that pin their own mode (either way) didn't change and are left alone.
  def self.to_acts!(production)
    new(production).to_acts!
  end

  # One show has just switched to acts (an override inside a role-based
  # production). If it casts from the production's roles and any of them
  # holds more than one person, it takes a copy of that lineup first — the
  # production's roles stay as they are for its siblings — with this show's
  # assignments carried over; then the show's own lineup is split.
  def self.to_acts_for_show!(show)
    new(show.production).to_acts_for_show!(show)
  end

  def initialize(production)
    @production = production
  end

  def to_acts!
    raise ArgumentError, "#{@production.name} is not act-based" unless @production.act_based?

    summary = Summary.new
    Role.transaction do
      summary.merge!(split_lineup!(@production.roles.production_roles, show: nil))

      @production.shows.where(use_custom_roles: true, casting_mode: nil).find_each do |show|
        summary.merge!(split_lineup!(show.custom_roles, show: show))
      end
    end
    summary
  end

  def to_acts_for_show!(show)
    raise ArgumentError, "Show #{show.id} is not act-based" unless show.act_based?

    summary = Summary.new
    Role.transaction do
      if show.use_custom_roles?
        summary.merge!(split_lineup!(show.custom_roles, show: show))
      elsif @production.roles.production_roles.castable.where("quantity > 1").exists?
        copy_production_lineup_keeping_cast!(show)
        summary.lineups_copied += 1
        summary.merge!(split_lineup!(show.custom_roles, show: show))
      end
      # else: nothing multi-slot to split — keep sharing the production's lineup.
    end
    summary
  end

  private

  # Split every multi-slot castable role in one lineup (the production's, or a
  # show's custom one). Assignments on a production role span every show that
  # casts from it; a custom role's assignments belong to its show only — either
  # way `role.show_person_role_assignments` is exactly the set to move.
  def split_lineup!(lineup_scope, show:)
    summary = Summary.new
    lineup = lineup_scope.reorder(position: :asc, created_at: :asc, id: :asc).to_a
    return summary if lineup.none? { |r| splittable?(r) }

    running_order = []
    lineup.each do |role|
      running_order << role
      next unless splittable?(role)

      assignments = role.show_person_role_assignments.order(:position, :id).to_a
      # One act per slot — and never fewer acts than the fullest night needs.
      most_cast_on_one_night = assignments.group_by(&:show_id).values.map(&:size).max || 0
      slots = [ role.quantity, most_cast_on_one_night ].max

      new_acts = (2..slots).map { copy_role_as_act(role, show: show) }
      role.update_columns(quantity: 1, updated_at: Time.current)
      summary.roles_split += 1
      summary.acts_created += new_acts.size

      assignments.group_by(&:show_id).each_value do |night|
        summary.merge!(move_slots!(role, new_acts, night))
      end

      running_order.concat(new_acts)
    end

    running_order.each_with_index do |role, index|
      role.update_columns(position: index) unless role.position == index
    end
    summary
  end

  def splittable?(role)
    role.castable? && role.quantity > 1
  end

  # A new act right after `role`: same name, category, restriction, and
  # eligible members. Position is settled when the whole order is renumbered.
  def copy_role_as_act(role, show:)
    eligibilities = role.restricted? ? role.role_eligibilities.to_a : []
    restricted = role.restricted? && eligibilities.any?

    act = Role.new(
      production: @production,
      show: show,
      name: role.name,
      category: role.category,
      quantity: 1,
      restricted: restricted,
      position: role.position
    )
    act.pending_eligible_member_ids = eligibilities.map { |e| "#{e.member_type}_#{e.member_id}" } if restricted
    act.save!

    eligibilities.each do |e|
      act.role_eligibilities.create!(member_type: e.member_type, member_id: e.member_id)
    end
    act
  end

  # One night's assignments on a role that's just been split: the person in
  # slot k moves to the k-th act (slot 1 stays on the original), taking their
  # cast notification and any vacancy they opened along.
  def move_slots!(role, new_acts, night)
    summary = Summary.new
    slots = new_acts.size + 1
    taken = {}

    night.each do |assignment|
      k = assignment.position if assignment.position.between?(1, slots) && !taken[assignment.position]
      k ||= (1..slots).find { |i| !taken[i] }
      taken[k] = true

      if k == 1
        assignment.update_columns(position: 1) unless assignment.position == 1
        next
      end

      act = new_acts[k - 2]
      assignment.update_columns(role_id: act.id, position: 1, updated_at: Time.current)
      summary.assignments_moved += 1
      next if assignment.assignable_id.blank? # a guest: nothing else keyed to them

      by_person = { show_id: assignment.show_id, role_id: role.id,
                    assignable_type: assignment.assignable_type, assignable_id: assignment.assignable_id }
      summary.notifications_moved +=
        ShowCastNotification.where(by_person).update_all(role_id: act.id, updated_at: Time.current)
      summary.vacancies_moved +=
        RoleVacancy.where(show_id: assignment.show_id, role_id: role.id,
                          vacated_by_type: assignment.assignable_type, vacated_by_id: assignment.assignable_id)
                   .update_all(role_id: act.id, updated_at: Time.current)
    end
    summary
  end

  # Give a show its own copy of the production's lineup with its cast intact:
  # every assignment (and notification / vacancy) on a production role moves
  # to the same-named custom role. Show#copy_roles_from_production! makes the
  # roles; the use_custom_roles flag is written directly so the model's
  # "clear the cast on toggle" hook doesn't fire.
  def copy_production_lineup_keeping_cast!(show)
    show.copy_roles_from_production!
    show.update_columns(use_custom_roles: true, updated_at: Time.current)

    custom_by_key = Role.match_keys_for(show.custom_roles.reload.to_a)
    production_roles = @production.roles.production_roles.to_a
    production_key_of = Role.match_keys_for(production_roles).invert

    production_roles.each do |source|
      target = custom_by_key[production_key_of[source]]
      next unless target

      show.show_person_role_assignments.where(role_id: source.id).update_all(role_id: target.id, updated_at: Time.current)
      ShowCastNotification.where(show_id: show.id, role_id: source.id).update_all(role_id: target.id, updated_at: Time.current)
      RoleVacancy.where(show_id: show.id, role_id: source.id).update_all(role_id: target.id, updated_at: Time.current)
    end
  end
end
