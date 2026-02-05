# frozen_string_literal: true

class AddOwnerToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_reference :organizations, :owner, null: true, foreign_key: { to_table: :users }

    # Set existing organizations to be owned by their first manager
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE organizations
          SET owner_id = (
            SELECT user_id FROM user_roles
            WHERE user_roles.organization_id = organizations.id
            AND user_roles.company_role = 'manager'
            LIMIT 1
          )
        SQL
      end
    end

    # Now make it required
    change_column_null :organizations, :owner_id, false
  end
end
