class AddCastingModeToProductions < ActiveRecord::Migration[8.0]
  def change
    # How a production casts: fill named positions ("role_based") or build a
    # running order of acts and cast each one ("act_based").
    add_column :productions, :casting_mode, :string, null: false, default: "role_based"
    add_index :productions, :casting_mode
  end
end
