class AddRoleFieldsToTeamInvitations < ActiveRecord::Migration[8.1]
  def change
    add_column :team_invitations, :invitation_role, :string, default: "viewer"
    add_column :team_invitations, :invitation_notifications_enabled, :boolean, default: true
  end
end
