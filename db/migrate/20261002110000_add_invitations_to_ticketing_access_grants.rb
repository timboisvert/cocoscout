# frozen_string_literal: true

# Door access for someone not on CocoScout yet: the grant waits as an
# invitation by email until they accept (making an account if they need one).
class AddInvitationsToTicketingAccessGrants < ActiveRecord::Migration[8.1]
  def change
    change_column_null :ticketing_access_grants, :user_id, true
    add_column :ticketing_access_grants, :invited_email, :string
    add_column :ticketing_access_grants, :invited_name, :string
    add_column :ticketing_access_grants, :invitation_token, :string
    add_column :ticketing_access_grants, :invited_at, :datetime
    add_column :ticketing_access_grants, :accepted_at, :datetime
    add_index :ticketing_access_grants, :invitation_token, unique: true
    add_index :ticketing_access_grants, %i[organization_id invited_email], unique: true,
              where: "revoked_at IS NULL AND user_id IS NULL", name: "idx_ticketing_access_grants_one_pending_invite"
  end
end
