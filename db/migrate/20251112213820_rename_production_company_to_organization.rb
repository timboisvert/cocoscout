class RenameProductionCompanyToOrganization < ActiveRecord::Migration[8.1]
  def change
    # Rename the main table
    rename_table :production_companies, :organizations

    # Rename foreign key columns (with safety checks)
    if column_exists?(:productions, :production_company_id)
      rename_column :productions, :production_company_id, :organization_id
    end

    if column_exists?(:user_roles, :production_company_id)
      rename_column :user_roles, :production_company_id, :organization_id
    end

    if table_exists?(:invitations) && column_exists?(:invitations, :production_company_id)
      rename_column :invitations, :production_company_id, :organization_id
    end

    if column_exists?(:person_invitations, :production_company_id)
      rename_column :person_invitations, :production_company_id, :organization_id
    end

    if column_exists?(:locations, :production_company_id)
      rename_column :locations, :production_company_id, :organization_id
    end

    # Rename join table
    if table_exists?(:people_production_companies)
      rename_table :people_production_companies, :organizations_people
    end

    if table_exists?(:organizations_people) && column_exists?(:organizations_people, :production_company_id)
      rename_column :organizations_people, :production_company_id, :organization_id
    end
  end
end
