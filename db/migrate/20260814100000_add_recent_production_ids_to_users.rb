class AddRecentProductionIdsToUsers < ActiveRecord::Migration[8.1]
  def change
    # Most-recently-used production ids (newest first) for the production
    # picker's "recently used" list — on the user row so it follows them
    # across devices.
    add_column :users, :recent_production_ids, :jsonb, default: [], null: false
  end
end
