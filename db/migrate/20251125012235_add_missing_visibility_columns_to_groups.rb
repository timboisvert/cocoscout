class AddMissingVisibilityColumnsToGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :groups, :videos_visible, :boolean, default: true, null: false
    add_column :groups, :performance_credits_visible, :boolean, default: true, null: false
  end
end
