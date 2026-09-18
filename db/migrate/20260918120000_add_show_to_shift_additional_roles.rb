# frozen_string_literal: true

# An "also covers" role on a shift that spans several shows can now name the
# shows it covers: a bartender who is also on tech for the 9pm show only.
# Before, the extra role applied to every show the shift covered, all or
# nothing, so multi-role work couldn't be consolidated into one shift without
# overclaiming coverage.
#
# NULL show_id keeps today's meaning — every show the shift covers — so existing
# rows need no backfill. Uniqueness splits in two because Postgres treats NULLs
# as distinct: one row per role when it covers everything, one per (role, show)
# when it's scoped.
class AddShowToShiftAdditionalRoles < ActiveRecord::Migration[8.1]
  def change
    # Cascade, not a plain foreign key: every path that deletes a show
    # (destroy_all, contract date removal, cancellations) would otherwise be
    # blocked by a coverage note pointing at it. The note means nothing once
    # the show is gone.
    add_reference :shift_additional_roles, :show, foreign_key: { on_delete: :cascade }, null: true

    remove_index :shift_additional_roles, [ :shift_id, :house_role_id ],
                 name: "idx_shift_additional_roles_unique", unique: true
    add_index :shift_additional_roles, [ :shift_id, :house_role_id ],
              name: "idx_shift_additional_roles_unique_all_shows", unique: true,
              where: "show_id IS NULL"
    add_index :shift_additional_roles, [ :shift_id, :house_role_id, :show_id ],
              name: "idx_shift_additional_roles_unique_per_show", unique: true,
              where: "show_id IS NOT NULL"
  end
end
