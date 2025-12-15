class AddProductionIdToTeamInvitations < ActiveRecord::Migration[8.1]
  def change
    add_reference :team_invitations, :production, null: true, foreign_key: true
  end
end
