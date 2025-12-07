class AddPublicProfileFeaturesToProductions < ActiveRecord::Migration[8.1]
  def change
    add_column :productions, :show_cast_members, :boolean, default: true, null: false
    add_column :productions, :show_upcoming_events, :boolean, default: true, null: false
    add_column :productions, :cast_talent_pool_ids, :text
  end
end
