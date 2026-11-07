# frozen_string_literal: true

# A bill's total is nil until it's known, so a real $0.00 (a month Amazon's
# credits paid in full) can be told from a total nobody has read yet.
class CompanyExpenseTotalCanBeUnknown < ActiveRecord::Migration[8.1]
  def up
    change_column_default :company_expenses, :bill_total_cents, from: 0, to: nil
    change_column_null :company_expenses, :bill_total_cents, true
    execute "UPDATE company_expenses SET bill_total_cents = NULL WHERE confirmed_at IS NULL AND bill_total_cents = 0"
  end

  def down
    execute "UPDATE company_expenses SET bill_total_cents = 0 WHERE bill_total_cents IS NULL"
    change_column_null :company_expenses, :bill_total_cents, false
    change_column_default :company_expenses, :bill_total_cents, from: nil, to: 0
  end
end
