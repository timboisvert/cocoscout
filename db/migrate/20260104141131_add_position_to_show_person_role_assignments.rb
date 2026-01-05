class AddPositionToShowPersonRoleAssignments < ActiveRecord::Migration[8.1]
  def change
    add_column :show_person_role_assignments, :position, :integer, default: 0, null: false

    add_index :show_person_role_assignments, [ :show_id, :role_id, :position ],
              name: "idx_assignments_show_role_position"
  end
end
