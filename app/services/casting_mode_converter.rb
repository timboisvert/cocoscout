# frozen_string_literal: true

# Reshapes a lineup between its role-based and act-based forms without losing
# anything.
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
# newly cast or removed; an open vacancy nobody's assignment accounts for lands
# on the first empty act. Rename the acts in the Lineup afterwards.
#
# Switching back to roles is the mirror image: a run of adjacent acts with the
# same name, category, restriction and eligible members ("Dancer, Dancer,
# Dancer, Dancer, Dancer") folds back into ONE role — the first act keeps its
# id and becomes "Dancer ×5", the others' assignments re-slot 1..n onto it (with
# their notifications and vacancies), and the folded acts are deleted. Breaks
# are deleted too: they aren't roles. Any names that still repeat afterwards
# (Magic at 1 and 3, with Clown between) get a " (2)" suffix so a role-based
# lineup keeps one role per name. Roles → acts → roles is a round trip.
#
# Show roles: a role-based lineup's technical roles (Stage Manager ×2) were
# never acts, so switching to acts marks them standing — "Show roles" cast
# alongside the lineup, slots kept — instead of splitting them into numbered
# acts. Standing roles are never split. Switching back to roles clears the
# flag (a role-based lineup has no running order to sit outside of); the
# category was kept, so a technical role comes back exactly as it was.
#
# Idempotent both ways: a lineup already in the requested shape is left
# untouched. Draft casting-table assignments stay on the surviving role.
class CastingModeConverter
  Summary = Struct.new(:roles_split, :acts_created, :assignments_moved,
                       :notifications_moved, :vacancies_moved, :lineups_copied,
                       :roles_merged, :acts_merged, :breaks_removed, :names_suffixed,
                       :roles_kept_standing, :standing_cleared,
                       keyword_init: true) do
    def initialize(**)
      super
      each_pair { |k, v| self[k] = v || 0 }
    end

    def changed?
      roles_split.positive? || lineups_copied.positive? || roles_merged.positive? ||
        breaks_removed.positive? || names_suffixed.positive? ||
        roles_kept_standing.positive? || standing_cleared.positive?
    end

    def merge!(other)
      each_pair { |k, v| self[k] = v + other[k] }
      self
    end
  end

  # The production has just switched to acts. A show that pins role mode and
  # casts from the production's roles first takes its own copy of that lineup
  # (cast carried over) so it keeps "Dancer ×5"; then the production's own
  # lineup is split, and so is the custom lineup of each show that inherits
  # the production's mode. Shows that pin their own mode didn't change and
  # their custom lineups are left alone.
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

  # The production has just switched back to roles: the mirror of .to_acts!.
  # A show that pins act mode and casts from the production's roles first
  # takes its own copy of the act lineup (cast carried over) so it keeps its
  # running order; then the production's lineup and the custom lineup of each
  # inheriting show are merged back into roles.
  def self.to_roles!(production)
    new(production).to_roles!
  end

  # One show has just gone back to roles (an override to role mode, or an
  # override cleared under a role-based production). Its own custom lineup is
  # merged back into roles and its breaks deleted; if it casts from an
  # act-based production's roles that would fold, it takes a role-shaped copy
  # of them first, cast carried over.
  def self.to_roles_for_show!(show)
    new(show.production).to_roles_for_show!(show)
  end

  # Group a lineup (breaks excluded, in running order) into runs of adjacent
  # castable roles that read as one role: same name, category, restriction and
  # eligible members — and the same standing, so a show role never folds into
  # a same-named act. Every role of a role-based lineup is its own run.
  # Returns an array of arrays of roles.
  def self.mergeable_runs(roles)
    list = roles.to_a.reject(&:break?)
    eligibilities = RoleEligibility.where(role_id: list.map(&:id)).group_by(&:role_id)
    key = lambda do |role|
      members = role.restricted? ? (eligibilities[role.id] || []).map { |e| [ e.member_type, e.member_id ] }.sort : []
      [ role.name.to_s.strip, role.category, role.standing?, role.restricted? && members.any?, members ]
    end
    list.slice_when { |a, b| key.call(a) != key.call(b) }.to_a
  end

  # The name a role-based lineup can hold: the name itself if `taken` doesn't
  # have it yet, else the first free "Name (2)", "Name (3)"… `taken` is a Set
  # of names already used and is updated with the returned name.
  def self.unique_name(name, taken)
    base = name.to_s.strip
    candidate = base
    n = 1
    while taken.include?(candidate)
      n += 1
      candidate = "#{base} (#{n})"
    end
    taken << candidate
    candidate
  end

  def initialize(production)
    @production = production
  end

  def to_acts!
    raise ArgumentError, "#{@production.name} is not act-based" unless @production.act_based?

    summary = Summary.new
    Role.transaction do
      production_lineup = @production.roles.production_roles
      # Only splitting reshapes the shared roles in a way a role-pinned show
      # would notice; marking technical roles standing is idle in role mode.
      if production_lineup.any? { |r| splittable?(r) }
        @production.shows.where(casting_mode: "role_based", use_custom_roles: false).find_each do |show|
          copy_production_lineup_keeping_cast!(show)
          summary.lineups_copied += 1
        end
      end

      summary.merge!(split_lineup!(production_lineup, show: nil))

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
      elsif @production.roles.production_roles.any? { |r| splittable?(r) || becomes_standing?(r) }
        # The production's roles are shared with every other night, so this
        # show takes its own copy before anything is split or marked.
        copy_production_lineup_keeping_cast!(show)
        summary.lineups_copied += 1
        summary.merge!(split_lineup!(show.custom_roles, show: show))
      end
      # else: nothing to reshape — keep sharing the production's lineup.
    end
    summary
  end

  def to_roles!
    raise ArgumentError, "#{@production.name} is not role-based" unless @production.role_based?

    summary = Summary.new
    Role.transaction do
      production_lineup = @production.roles.production_roles
      if mergeable?(production_lineup)
        @production.shows.where(casting_mode: "act_based", use_custom_roles: false).find_each do |show|
          copy_production_lineup_keeping_cast!(show)
          summary.lineups_copied += 1
        end
      end

      summary.merge!(merge_lineup!(production_lineup, show: nil))

      @production.shows.where(use_custom_roles: true, casting_mode: nil).find_each do |show|
        summary.merge!(merge_lineup!(show.custom_roles, show: show))
      end
    end
    summary
  end

  def to_roles_for_show!(show)
    raise ArgumentError, "Show #{show.id} is not role-based" unless show.role_based?

    summary = Summary.new
    Role.transaction do
      if show.use_custom_roles?
        summary.merge!(merge_lineup!(show.custom_roles, show: show))
      elsif mergeable?(@production.roles.production_roles)
        # Show#copy_roles_from_production! copies role-shaped for a role-based
        # show, so the copy lands already merged and the cast re-slotted.
        copy_production_lineup_keeping_cast!(show)
        summary.lineups_copied += 1
      end
      # else: the production's roles read fine as roles — keep sharing them.
    end
    summary
  end

  private

  # ---- roles → acts ---------------------------------------------------------

  # Split every multi-slot castable role in one lineup (the production's, or a
  # show's custom one). Assignments on a production role span every show that
  # casts from it; a custom role's assignments belong to its show only — either
  # way `role.show_person_role_assignments` is exactly the set to move.
  def split_lineup!(lineup_scope, show:)
    summary = Summary.new
    lineup = lineup_scope.reorder(position: :asc, created_at: :asc, id: :asc).to_a

    # Technical roles were never acts: they become show roles, slots intact.
    lineup.select { |r| becomes_standing?(r) }.each do |role|
      role.update_columns(standing: true, updated_at: Time.current)
      summary.roles_kept_standing += 1
    end
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
      summary.merge!(seat_open_vacancies!(role, new_acts))

      running_order.concat(new_acts)
    end

    renumber!(running_order)
    summary
  end

  # A show role isn't an act, whatever its slot count — it's never split.
  def splittable?(role)
    role.castable? && !role.standing? && !becomes_standing?(role) && role.quantity > 1
  end

  def becomes_standing?(role)
    role.category == "technical" && !role.standing?
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
      standing: false,
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

  # Open vacancies still on the split role that no moved assignment accounts
  # for (the person who left is no longer cast, or nobody in particular left)
  # each take the first empty act of their night, so the vacancy shows on the
  # open slot and filling it fills that act, not act 1.
  def seat_open_vacancies!(role, new_acts)
    summary = Summary.new
    acts = [ role, *new_acts ]
    stranded = RoleVacancy.active.where(role_id: role.id).order(:created_at, :id).group_by(&:show_id)
    return summary if stranded.empty?

    occupied = ShowPersonRoleAssignment.where(show_id: stranded.keys, role_id: acts.map(&:id))
                                       .pluck(:show_id, :role_id, :assignable_type, :assignable_id).group_by(&:first)
    stranded.each do |show_id, vacancies|
      night = occupied[show_id] || []
      filled = night.map { |row| row[1] }.to_set
      still_cast_on_act_one = night.select { |row| row[1] == role.id }.map { |row| [ row[2], row[3] ] }.to_set
      vacancies.each do |vacancy|
        # Whoever opened it is still cast in slot 1 (a linked show keeps the
        # assignment while a replacement is sought): the vacancy is theirs.
        next if vacancy.vacated_by_id && still_cast_on_act_one.include?([ vacancy.vacated_by_type, vacancy.vacated_by_id ])

        empty_act = acts.find { |act| !filled.include?(act.id) }
        break unless empty_act # every act is cast: the vacancy stays where it is

        filled << empty_act.id
        next if empty_act.id == role.id

        vacancy.update_columns(role_id: empty_act.id, updated_at: Time.current)
        summary.vacancies_moved += 1
      end
    end
    summary
  end

  # ---- acts → roles ---------------------------------------------------------

  # Would merging this lineup change it? True when it holds a break, a show
  # role, a run of adjacent look-alike acts, or a repeated name.
  def mergeable?(lineup_scope)
    lineup = lineup_scope.reorder(position: :asc, created_at: :asc, id: :asc).to_a
    return true if lineup.any? { |r| r.break? || r.standing? }

    runs = self.class.mergeable_runs(lineup)
    runs.any? { |run| run.size > 1 } || lineup.map { |r| r.name.to_s.strip }.uniq.size < lineup.size
  end

  # Fold one lineup back into roles: adjacent look-alike acts become one
  # multi-slot role, breaks go, show roles become plain roles, leftover
  # repeated names get suffixed, and the running order is renumbered.
  def merge_lineup!(lineup_scope, show:)
    summary = Summary.new
    return summary unless mergeable?(lineup_scope)

    lineup = lineup_scope.reorder(position: :asc, created_at: :asc, id: :asc).to_a
    lineup.select(&:break?).each do |brk|
      brk.destroy!
      summary.breaks_removed += 1
    end
    lineup.select(&:standing?).each do |role|
      role.update_columns(standing: false, updated_at: Time.current)
      summary.standing_cleared += 1
    end

    survivors = self.class.mergeable_runs(lineup).map do |run|
      survivor, *folded = run
      summary.merge!(fold_acts!(survivor, folded)) if folded.any?
      survivor
    end

    taken = Set.new
    survivors.each do |role|
      name = self.class.unique_name(role.name, taken)
      next if name == role.name

      role.update_columns(name: name, updated_at: Time.current)
      summary.names_suffixed += 1
    end

    renumber!(survivors)
    summary
  end

  # Merge `folded` acts into `survivor`: every night's assignments across the
  # run re-slot 1..n on the survivor (in running order), notifications,
  # vacancies, drafts and sign-up slots re-point to it, and the folded acts are
  # deleted. The survivor holds as many slots as acts merged — or as many
  # people as its fullest night, if a night somehow held more.
  def fold_acts!(survivor, folded)
    summary = Summary.new(roles_merged: 1, acts_merged: folded.size)
    run = [ survivor, *folded ]
    folded_ids = folded.map(&:id)

    assignments = ShowPersonRoleAssignment.where(role_id: run.map(&:id)).order(:position, :id).to_a
    order_of = run.each_with_index.to_h { |r, i| [ r.id, i ] }
    quantity = run.sum(&:quantity)

    assignments.group_by(&:show_id).each_value do |night|
      seated, moved = reseat!(survivor, night.sort_by { |a| [ order_of[a.role_id], a.position, a.id ] })
      summary.assignments_moved += moved
      quantity = [ quantity, seated ].max
    end

    summary.notifications_moved += repoint_notifications!(survivor, folded_ids)
    summary.vacancies_moved += RoleVacancy.where(role_id: folded_ids).update_all(role_id: survivor.id, updated_at: Time.current)
    repoint_draft_assignments!(survivor, folded_ids)
    SignUpSlot.where(role_id: folded_ids).update_all(role_id: survivor.id)

    survivor.update_columns(quantity: quantity, updated_at: Time.current)
    folded.each(&:destroy!)
    summary
  end

  # Seat one night's assignments (already in running order) on `target` in
  # slots 1..n. Returns [slots seated, assignments that changed role]. The
  # same person holding two acts of a run is seated once — a role holds a
  # person once — and their second assignment is dropped.
  def reseat!(target, assignments)
    seated = Set.new
    slot = 0
    moved = 0
    assignments.each do |assignment|
      person = [ assignment.assignable_type, assignment.assignable_id ] if assignment.assignable_id.present?
      if person && seated.include?(person)
        assignment.destroy!
        next
      end
      seated << person if person

      slot += 1
      moved += 1 if assignment.role_id != target.id
      assignment.update_columns(role_id: target.id, position: slot, updated_at: Time.current)
    end
    [ slot, moved ]
  end

  # Cast notifications on `source_ids` move to `target` (within one show when
  # show_id is given). A person notified for two acts of a run keeps one.
  def repoint_notifications!(target, source_ids, show_id: nil)
    moved = 0
    scope = ShowCastNotification.where(role_id: source_ids)
    scope = scope.where(show_id: show_id) if show_id
    scope.find_each do |note|
      duplicate = ShowCastNotification.where(show_id: note.show_id, role_id: target.id,
                                             assignable_type: note.assignable_type, assignable_id: note.assignable_id,
                                             notification_type: note.notification_type).exists?
      if duplicate
        note.destroy!
      else
        note.update_columns(role_id: target.id, updated_at: Time.current)
        moved += 1
      end
    end
    moved
  end

  def repoint_draft_assignments!(survivor, folded_ids)
    CastingTableDraftAssignment.where(role_id: folded_ids).find_each do |draft|
      duplicate = CastingTableDraftAssignment.where(casting_table_id: draft.casting_table_id, show_id: draft.show_id,
                                                    role_id: survivor.id, assignable_type: draft.assignable_type,
                                                    assignable_id: draft.assignable_id).exists?
      duplicate ? draft.destroy! : draft.update_columns(role_id: survivor.id, updated_at: Time.current)
    end
  end

  # ---- shared -----------------------------------------------------------------

  def renumber!(running_order)
    running_order.each_with_index do |role, index|
      role.update_columns(position: index) unless role.position == index
    end
  end

  # Give a show its own copy of the production's lineup with its cast intact:
  # every assignment (and notification / vacancy) on a production role moves
  # to the custom role copied from it. Show#copy_roles_from_production! makes
  # the roles — in the show's own shape, so a role-based show under an act
  # lineup gets "Dancer ×3" for three Dancer acts and its cast re-slotted 1..n
  # — and says which copy came from which. The use_custom_roles flag is
  # written directly so the model's "clear the cast on toggle" hook doesn't
  # fire.
  def copy_production_lineup_keeping_cast!(show)
    copied_from = show.copy_roles_from_production!
    show.update_columns(use_custom_roles: true, updated_at: Time.current)

    copied_from.group_by { |_source_id, target| target }.each do |target, pairs|
      source_ids = pairs.map(&:first)
      assignments = show.show_person_role_assignments.where(role_id: source_ids).order(:position, :id).to_a
      if source_ids.size == 1
        ShowPersonRoleAssignment.where(id: assignments.map(&:id)).update_all(role_id: target.id, updated_at: Time.current)
      else
        order_of = source_ids.each_with_index.to_h
        seated, _moved = reseat!(target, assignments.sort_by { |a| [ order_of[a.role_id], a.position, a.id ] })
        target.update_columns(quantity: seated, updated_at: Time.current) if seated > target.quantity
      end
      repoint_notifications!(target, source_ids, show_id: show.id)
      RoleVacancy.where(show_id: show.id, role_id: source_ids).update_all(role_id: target.id, updated_at: Time.current)
    end
  end
end
