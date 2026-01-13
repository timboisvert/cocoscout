class AddNonRevenueOverrideToShowFinancials < ActiveRecord::Migration[8.1]
  def change
    add_column :show_financials, :non_revenue_override, :boolean, default: false, null: false
  end
end
