class RenameInvitationsToTeamInvitations < ActiveRecord::Migration[7.0]
  def change
    rename_table :invitations, :team_invitations
  end
end
