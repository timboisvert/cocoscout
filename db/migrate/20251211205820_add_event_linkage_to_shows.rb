class AddEventLinkageToShows < ActiveRecord::Migration[8.1]
  def change
    add_reference :shows, :event_linkage, null: true, foreign_key: true
    add_column :shows, :linkage_role, :string
  end
end
