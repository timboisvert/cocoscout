# frozen_string_literal: true

# Books V1.3, plan D3 and §9.13: a bank statement brought in as a file. The
# file itself is never stored; what stays is one row per line (date, amount,
# the bank's description) and the import that brought them.
class CreateBankStatementImports < ActiveRecord::Migration[8.1]
  def change
    create_table :bank_statement_imports do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :imported_by, foreign_key: { to_table: :users }
      t.string :filename
      t.string :format, null: false, default: "csv"
      t.date :from_on
      t.date :to_on
      t.integer :lines_count, null: false, default: 0
      t.integer :new_lines_count, null: false, default: 0
      t.bigint :closing_balance_cents
      t.date :closing_on
      t.timestamps
    end

    create_table :bank_statement_lines do |t|
      t.references :bank_statement_import, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.date :on, null: false
      t.bigint :amount_cents, null: false
      t.string :description, null: false, default: ""
      t.string :fingerprint, null: false
      t.string :state, null: false, default: "open"
      t.references :journal_line, foreign_key: true
      t.references :money_record, foreign_key: true
      t.timestamps
    end
    add_index :bank_statement_lines, %i[organization_id fingerprint], unique: true
    add_index :bank_statement_lines, %i[organization_id state on]
  end
end
