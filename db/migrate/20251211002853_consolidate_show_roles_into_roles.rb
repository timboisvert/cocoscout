class ConsolidateShowRolesIntoRoles < ActiveRecord::Migration[8.1]
  def up
    # Step 1: Add show_id to roles table (optional - for show-specific roles)
    add_column :roles, :show_id, :integer
    add_index :roles, :show_id

    # Step 2: Migrate show_roles to roles
    # We need to track the mapping from old show_role_id to new role_id
    execute <<-SQL
      INSERT INTO roles (name, position, restricted, production_id, show_id, created_at, updated_at)
      SELECT#{' '}
        sr.name,#{' '}
        sr.position,#{' '}
        sr.restricted,#{' '}
        s.production_id,
        sr.show_id,
        sr.created_at,#{' '}
        sr.updated_at
      FROM show_roles sr
      JOIN shows s ON s.id = sr.show_id
    SQL

    # Step 3: Create a temporary mapping table for show_role_id -> role_id
    execute <<-SQL
      CREATE TEMPORARY TABLE show_role_to_role_mapping AS
      SELECT#{' '}
        sr.id as show_role_id,
        r.id as role_id
      FROM show_roles sr
      JOIN shows s ON s.id = sr.show_id
      JOIN roles r ON r.show_id = sr.show_id#{' '}
                  AND r.name = sr.name#{' '}
                  AND r.production_id = s.production_id
    SQL

    # Step 4: Migrate show_role_eligibilities to role_eligibilities
    execute <<-SQL
      INSERT INTO role_eligibilities (role_id, member_type, member_id, created_at, updated_at)
      SELECT#{' '}
        m.role_id,
        sre.member_type,
        sre.member_id,
        sre.created_at,
        sre.updated_at
      FROM show_role_eligibilities sre
      JOIN show_role_to_role_mapping m ON m.show_role_id = sre.show_role_id
    SQL

    # Step 5: Update show_person_role_assignments - convert show_role_id to role_id
    execute <<-SQL
      UPDATE show_person_role_assignments
      SET role_id = (
        SELECT m.role_id#{' '}
        FROM show_role_to_role_mapping m#{' '}
        WHERE m.show_role_id = show_person_role_assignments.show_role_id
      )
      WHERE show_role_id IS NOT NULL
    SQL

    # Step 6: Update role_vacancies - convert show_role_id to role_id
    execute <<-SQL
      UPDATE role_vacancies
      SET role_id = (
        SELECT m.role_id#{' '}
        FROM show_role_to_role_mapping m#{' '}
        WHERE m.show_role_id = role_vacancies.show_role_id
      )
      WHERE show_role_id IS NOT NULL
    SQL

    # Step 7: Remove show_role_id columns
    remove_column :show_person_role_assignments, :show_role_id
    remove_column :role_vacancies, :show_role_id

    # Step 8: Drop the old tables
    drop_table :show_role_eligibilities
    drop_table :show_roles

    # Step 9: Add foreign key for show_id on roles
    add_foreign_key :roles, :shows, column: :show_id, on_delete: :cascade

    # Step 10: Update uniqueness constraint on roles to include show_id
    # Remove old index and add new one that accounts for show_id
    remove_index :roles, :production_id if index_exists?(:roles, :production_id)
    add_index :roles, [ :production_id, :show_id, :name ], unique: true, name: "index_roles_on_production_show_name"
  end

  def down
    # This migration is not easily reversible - would need to recreate show_roles
    raise ActiveRecord::IrreversibleMigration, "Cannot reverse consolidation of show_roles into roles"
  end
end
