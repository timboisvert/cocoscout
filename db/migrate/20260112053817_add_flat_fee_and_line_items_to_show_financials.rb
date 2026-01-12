class AddFlatFeeAndLineItemsToShowFinancials < ActiveRecord::Migration[8.1]
  def change
    add_column :show_financials, :revenue_type, :string, default: "ticket_sales"
    add_column :show_financials, :flat_fee, :decimal, precision: 10, scale: 2
    add_column :show_financials, :other_revenue_details, :jsonb, default: []
    add_column :show_financials, :expense_details, :jsonb, default: []
  end
end
