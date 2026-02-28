class AddInventoryModeToProductionTicketingSetups < ActiveRecord::Migration[8.1]
  def change
    add_column :production_ticketing_setups, :inventory_mode, :string, default: "unified", null: false
  end
end
