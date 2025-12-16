class AddAuditionVotingEnabledToAuditionCycles < ActiveRecord::Migration[8.1]
  def change
    add_column :audition_cycles, :audition_voting_enabled, :boolean, default: true, null: false
  end
end
