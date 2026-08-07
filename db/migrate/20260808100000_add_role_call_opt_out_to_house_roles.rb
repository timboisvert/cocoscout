# frozen_string_literal: true

# Role Call checks every per-show role on every show. Some roles genuinely
# aren't a per-show expectation — a videographer who only shoots occasionally
# shouldn't flag every show that doesn't have one. Opting a role out is a
# property of the role, not of each show.
#
# Defaults to true so an org that already has Role Call on sees no change.
class AddRoleCallOptOutToHouseRoles < ActiveRecord::Migration[8.1]
  def change
    add_column :house_roles, :include_in_role_call, :boolean, default: true, null: false
  end
end
