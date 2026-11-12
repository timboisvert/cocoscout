# frozen_string_literal: true

# A statement's lines are matched to the books in a job after the upload
# (Tim, 2026-11-02: the import was one heavy request). The import carries
# its status and what the job found; a line can match a group of lines on
# the books (one bank deposit, several entries), and remembers a key of its
# description so what you did with "CHICAGO LUMBER" last month is offered
# again this month.
class BankStatementImportsRunInTheBackground < ActiveRecord::Migration[8.1]
  def change
    change_table :bank_statement_imports, bulk: true do |t|
      t.string :status, null: false, default: "ready"
      t.integer :matched_count, null: false, default: 0
      t.integer :suggested_count, null: false, default: 0
      t.bigint :opening_balance_cents
      t.date :opening_on
      t.string :error
    end
    change_table :bank_statement_lines, bulk: true do |t|
      t.bigint :journal_line_ids, array: true, null: false, default: []
      t.string :description_key
      t.index %i[organization_id description_key], name: "index_bank_statement_lines_on_org_and_description_key"
    end
  end
end
