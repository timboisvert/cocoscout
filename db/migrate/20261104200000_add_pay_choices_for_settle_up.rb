# frozen_string_literal: true

# Paying people from the day's Settle up page (Tim, 2026-11-04). Each
# calculated line carries the manager's choice for it: on the payout run
# when the day settles (the default), or held back for now; "paid another
# way" is the existing manually_paid. A production says whether its
# calculation is chosen once for every show or asked for each show.
class AddPayChoicesForSettleUp < ActiveRecord::Migration[8.1]
  def change
    add_column :show_payout_line_items, :pay_choice, :string, default: "run", null: false
    add_column :productions, :payout_calculation_mode, :string, default: "production", null: false
  end
end
