class AddServicesToContracts < ActiveRecord::Migration[8.1]
  def change
    add_column :contracts, :services, :jsonb, default: []
  end
end
