class AddAdvanceAndPayrollFieldsToShowPayoutLineItems < ActiveRecord::Migration[8.1]
  def change
    # Advance tracking
    add_column :show_payout_line_items, :advance_deduction, :decimal, precision: 10, scale: 2, default: 0

    # Payroll tracking
    add_reference :show_payout_line_items, :payroll_line_item, null: true, foreign_key: true
    add_column :show_payout_line_items, :paid_independently, :boolean, default: false
  end
end
