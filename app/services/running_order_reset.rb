# frozen_string_literal: true

# Resets an act-based show's running order back to the production's default
# lineup. Assignments survive when a same-named act (or show role) exists in
# the default — matched by name + ordinal (Role.match_key_for), so the second
# "Magic" maps to the second "Magic" — and are wiped with their act otherwise.
#
# #preview says what would happen (for the confirm modal); #perform! does it.
class RunningOrderReset
  def initialize(show)
    @show = show
    @production = show.production
  end

  # {
  #   new_lineup: [{ name:, kind: "act"|"intermission"|"show_role", number: }],
  #   migrated:   [{ name: "Trixie", from: "Magic (Act 1)", to: "Magic (Act 1)" }],
  #   wiped:      [{ name: "Trixie", from: "Burlesque (Act 7)" }]
  # }
  def preview
    new_numbers = Role.lineup_numbers_for(default_roles)

    migrated = []
    wiped = []
    assignments.each do |assignment|
      member = member_name(assignment)
      next if member.blank?

      old_role = old_roles_by_id[assignment.role_id]
      next if old_role.nil?

      target = new_roles_by_key[old_key_by_role_id[assignment.role_id]]
      if target
        migrated << { name: member, from: label(old_role, old_numbers), to: label(target, new_numbers) }
      else
        wiped << { name: member, from: label(old_role, old_numbers) }
      end
    end

    {
      new_lineup: default_roles.map do |role|
        kind = if role.break?
          "intermission"
        else
          role.standing? ? "show_role" : "act"
        end
        { name: role.name, kind: kind, number: new_numbers[role.id] }
      end,
      migrated: migrated,
      wiped: wiped
    }
  end

  def perform!
    @show.transaction do
      snapshot = assignments.map do |a|
        {
          key: old_key_by_role_id[a.role_id],
          assignable_type: a.assignable_type,
          assignable_id: a.assignable_id,
          guest_name: a.guest_name,
          guest_email: a.guest_email
        }
      end
      # Which role each notification described, by match key, so the records
      # follow their acts through the reset. Rows whose act doesn't survive
      # keep a nil role (Role nullifies) — the evidence a removal notice is owed.
      notification_keys = @show.show_cast_notifications.each_with_object({}) do |note, hash|
        hash[note.id] = old_key_by_role_id[note.role_id] if note.role_id
      end

      @show.custom_roles.destroy_all
      copied_from = @show.copy_roles_from_production!
      @show.update_columns(use_custom_roles: true, updated_at: Time.current)

      key_to_copy = Role.match_keys_for(default_roles).transform_values { |r| copied_from[r.id] }
      snapshot.each do |entry|
        target = key_to_copy[entry[:key]]
        next if target.nil?

        @show.show_person_role_assignments.create!(
          role: target,
          assignable_type: entry[:assignable_type],
          assignable_id: entry[:assignable_id],
          guest_name: entry[:guest_name],
          guest_email: entry[:guest_email]
        )
      end

      @show.show_cast_notifications.reload.each do |note|
        target = key_to_copy[notification_keys[note.id]]
        note.update_columns(role_id: target.id) if target
      end
    end
  end

  private

  def default_roles
    @default_roles ||= @production.roles.production_roles.to_a
  end

  def old_roles
    @old_roles ||= @show.available_roles.to_a
  end

  def old_roles_by_id
    @old_roles_by_id ||= old_roles.index_by(&:id)
  end

  def old_numbers
    @old_numbers ||= Role.lineup_numbers_for(old_roles)
  end

  def old_key_by_role_id
    @old_key_by_role_id ||= Role.match_keys_for(old_roles).each_with_object({}) { |(key, role), hash| hash[role.id] = key }
  end

  def new_roles_by_key
    @new_roles_by_key ||= Role.match_keys_for(default_roles)
  end

  def assignments
    @assignments ||= @show.show_person_role_assignments.includes(:assignable).to_a
  end

  def member_name(assignment)
    assignment.guest? ? assignment.guest_name : assignment.assignable&.name
  end

  def label(role, numbers)
    number = numbers[role.id]
    number ? "#{role.name} (Act #{number})" : role.name
  end
end
