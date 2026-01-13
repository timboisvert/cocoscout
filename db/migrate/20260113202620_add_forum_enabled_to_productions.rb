class AddForumEnabledToProductions < ActiveRecord::Migration[8.1]
  def change
    add_column :productions, :forum_enabled, :boolean, default: true, null: false
  end
end
