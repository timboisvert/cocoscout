class AddShowRoleToRoleVacancies < ActiveRecord::Migration[8.1]
  def change
    # Add show_role_id for custom show roles
    add_column :role_vacancies, :show_role_id, :integer
    add_index :role_vacancies, :show_role_id

    # Make role_id nullable (vacancies can be for either production roles OR show roles)
    change_column_null :role_vacancies, :role_id, true

    # Add foreign key for show_role
    add_foreign_key :role_vacancies, :show_roles, column: :show_role_id, on_delete: :cascade
  end
end
