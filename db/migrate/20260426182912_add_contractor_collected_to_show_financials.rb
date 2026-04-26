class AddContractorCollectedToShowFinancials < ActiveRecord::Migration[8.1]
  def change
    add_column :show_financials, :contractor_collected, :decimal, precision: 10, scale: 2
  end
end
