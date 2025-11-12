class RenameProductionCompanyToOrganization < ActiveRecord::Migration[8.1]
  def change
    # Rename the main table
    rename_table :production_companies, :organizations

    # Rename foreign key columns
    rename_column :productions, :production_company_id, :organization_id
    rename_column :user_roles, :production_company_id, :organization_id
    rename_column :invitations, :production_company_id, :organization_id
    rename_column :person_invitations, :production_company_id, :organization_id
    rename_column :locations, :production_company_id, :organization_id

    # Rename join table
    rename_table :people_production_companies, :organizations_people
    rename_column :organizations_people, :production_company_id, :organization_id
  end
end
