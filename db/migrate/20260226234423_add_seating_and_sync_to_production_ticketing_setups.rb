class AddSeatingAndSyncToProductionTicketingSetups < ActiveRecord::Migration[8.1]
  def change
    add_reference :production_ticketing_setups, :seating_configuration, null: true, foreign_key: true
    add_column :production_ticketing_setups, :last_synced_at, :datetime
  end
end
