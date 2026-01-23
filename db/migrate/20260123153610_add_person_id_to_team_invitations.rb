class AddPersonIdToTeamInvitations < ActiveRecord::Migration[8.1]
  def change
    add_column :team_invitations, :person_id, :bigint
  end
end
