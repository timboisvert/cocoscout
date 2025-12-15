class AddReviewerAccessTypeToAuditionCycles < ActiveRecord::Migration[8.1]
  def change
    add_column :audition_cycles, :reviewer_access_type, :string, default: "managers", null: false
  end
end
