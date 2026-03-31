class AddCoverageTypeToFeatureCredits < ActiveRecord::Migration[8.1]
  def change
    add_column :feature_credits, :coverage_type, :string, default: "full", null: false
  end
end
