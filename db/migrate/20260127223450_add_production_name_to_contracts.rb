class AddProductionNameToContracts < ActiveRecord::Migration[8.1]
  def change
    add_column :contracts, :production_name, :string
  end
end
