# frozen_string_literal: true

class ConvertShowPersonRoleAssignmentsToPolymorphic < ActiveRecord::Migration[8.0]
  def up
    # Add polymorphic columns
    add_column :show_person_role_assignments, :assignable_type, :string
    add_column :show_person_role_assignments, :assignable_id, :bigint

    # Migrate existing data
    execute <<-SQL
      UPDATE show_person_role_assignments
      SET assignable_type = 'Person', assignable_id = person_id
      WHERE person_id IS NOT NULL
    SQL

    # Add index on polymorphic columns
    add_index :show_person_role_assignments, %i[assignable_type assignable_id],
              name: 'index_show_role_assignments_on_assignable'

    # Remove old person_id column (but keep it for now for rollback safety)
    # We'll remove it in a separate migration after verifying everything works
  end

  def down
    # Restore person_id from assignable columns if needed
    execute <<-SQL
      UPDATE show_person_role_assignments
      SET person_id = assignable_id
      WHERE assignable_type = 'Person' AND person_id IS NULL
    SQL

    remove_index :show_person_role_assignments, name: 'index_show_role_assignments_on_assignable'
    remove_column :show_person_role_assignments, :assignable_type
    remove_column :show_person_role_assignments, :assignable_id
  end
end
