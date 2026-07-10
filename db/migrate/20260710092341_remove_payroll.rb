# frozen_string_literal: true

# Removes the Payroll system (runs, line items, schedules). Poorly conceived and
# unused; superseded by the payout/balance model.
class RemovePayroll < ActiveRecord::Migration[8.1]
  def up
    # Drop the link from show payout line items to payroll first.
    remove_foreign_key :show_payout_line_items, :payroll_line_items, if_exists: true
    remove_column :show_payout_line_items, :payroll_line_item_id, if_exists: true

    drop_table :payroll_line_items, if_exists: true
    drop_table :payroll_runs, if_exists: true
    drop_table :payroll_schedules, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
