class AddDecisionTypeToCastAssignmentStages < ActiveRecord::Migration[8.1]
  def change
    add_column :cast_assignment_stages, :decision_type, :integer, default: 0, null: false
  end
end
