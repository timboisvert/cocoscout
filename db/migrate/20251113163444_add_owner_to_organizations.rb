# frozen_string_literal: true

class AddOwnerToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_reference :organizations, :owner, null: true, foreign_key: { to_table: :users }

    # Set existing organizations to be owned by their first manager
    reversible do |dir|
      dir.up do
        Organization.reset_column_information
        Organization.find_each do |org|
          manager = org.user_roles.find_by(company_role: 'manager')&.user
          org.update_column(:owner_id, manager&.id) if manager
        end
      end
    end

    # Now make it required
    change_column_null :organizations, :owner_id, false
  end
end
