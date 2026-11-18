# frozen_string_literal: true

# Month-end balances (Books V1.3): what each account moved in each finished
# month, by when it was earned and by when the money moved, so a balance is
# those months added up plus the few weeks of lines since. Without it every
# balance summed every line the organization ever posted (BooksBalances).
class CreateLedgerMonthBalances < ActiveRecord::Migration[8.1]
  def change
    create_table :ledger_month_balances do |t|
      t.references :organization, null: false, foreign_key: true, index: false
      t.references :ledger_account, null: false, foreign_key: true, index: false
      t.date :month, null: false
      t.bigint :accrual_cents, null: false, default: 0
      t.bigint :cash_cents, null: false, default: 0
      t.timestamps
      t.index %i[ledger_account_id month], unique: true
      t.index %i[organization_id month]
    end
    # The last day of the latest month whose balances are kept: every month
    # up to it is right, every later day is added up from the lines. A row
    # of its own, not a column on the organization: only BooksBalances
    # touches it, so a posting and the nightly roll can't lock each other.
    create_table :books_rollups do |t|
      t.references :organization, null: false, foreign_key: true, index: { unique: true }
      t.date :rolled_through, null: false
      t.timestamps
    end
  end
end
