class AddDataConfirmedToShowFinancials < ActiveRecord::Migration[8.1]
  def change
    add_column :show_financials, :data_confirmed, :boolean
  end
end
