class AddCastingSourceToProductions < ActiveRecord::Migration[8.1]
  def change
    add_column :productions, :casting_source, :string, default: "talent_pool", null: false
    add_index :productions, :casting_source
  end
end
