class AddRevenueProjectionsToContracts < ActiveRecord::Migration[8.1]
  def change
    add_column :contracts, :revenue_projections, :jsonb, default: {}
  end
end
