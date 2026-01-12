class AddUniqueIndexToShowPersonRoleAssignments < ActiveRecord::Migration[8.1]
  def change
    # Prevent the same person/group from being assigned to the same role on the same show
    # Uses a partial index to only apply when assignable_id is not null (guest assignments excluded)
    add_index :show_person_role_assignments,
              [ :show_id, :role_id, :assignable_type, :assignable_id ],
              unique: true,
              where: "assignable_id IS NOT NULL",
              name: "idx_unique_show_role_assignable"
  end
end
