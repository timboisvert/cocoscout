class AddTicketFeesToShowFinancials < ActiveRecord::Migration[8.1]
  def change
    add_column :show_financials, :ticket_fees, :jsonb, default: []
  end
end
