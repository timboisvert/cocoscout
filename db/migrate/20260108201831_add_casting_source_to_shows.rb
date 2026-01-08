class AddCastingSourceToShows < ActiveRecord::Migration[8.1]
  def change
    add_column :shows, :casting_source, :string, default: "talent_pool", null: false
    add_index :shows, :casting_source
  end
end
