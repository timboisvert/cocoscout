class AddPersonIdToOrganizationRoles < ActiveRecord::Migration[8.1]
  def change
    add_column :organization_roles, :person_id, :bigint
  end
end
