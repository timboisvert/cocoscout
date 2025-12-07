# frozen_string_literal: true

class MakeOrganizationOptionalOnPersonInvitations < ActiveRecord::Migration[8.1]
  def change
    change_column_null :person_invitations, :organization_id, true
  end
end
