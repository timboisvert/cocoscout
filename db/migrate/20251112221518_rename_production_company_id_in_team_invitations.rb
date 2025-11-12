class RenameProductionCompanyIdInTeamInvitations < ActiveRecord::Migration[8.1]
  def change
    rename_column :team_invitations, :production_company_id, :organization_id
  end
end
