class AddVotingEnabledToAuditionCycles < ActiveRecord::Migration[8.1]
  def change
    add_column :audition_cycles, :voting_enabled, :boolean, default: true, null: false
  end
end
