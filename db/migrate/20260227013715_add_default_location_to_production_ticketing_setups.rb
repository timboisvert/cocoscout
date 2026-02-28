class AddDefaultLocationToProductionTicketingSetups < ActiveRecord::Migration[8.1]
  def change
    # venue_mode: "show_location" (use each show's location), "org_location" (use default_location), "online"
    add_column :production_ticketing_setups, :venue_mode, :string, default: "show_location", null: false
    add_reference :production_ticketing_setups, :default_location, null: true, foreign_key: { to_table: :locations }
  end
end
