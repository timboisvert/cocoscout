# frozen_string_literal: true

# Access by module (Books V1.3, plan §9.11): a person on the organization's
# team can be given each module at none, view or manage, starting from a
# template (Bookkeeper, Box office, ...). Owners and managers keep everything
# and never carry grants; a viewer without grants keeps today's meaning.
class AddModuleGrantsToOrganizationRoles < ActiveRecord::Migration[8.0]
  def change
    add_column :organization_roles, :module_grants, :jsonb, null: false, default: {}
    add_column :organization_roles, :access_template, :string
  end
end
