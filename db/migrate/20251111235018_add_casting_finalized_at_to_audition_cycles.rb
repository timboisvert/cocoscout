class AddCastingFinalizedAtToAuditionCycles < ActiveRecord::Migration[8.1]
  def change
    add_column :audition_cycles, :casting_finalized_at, :datetime
  end
end
