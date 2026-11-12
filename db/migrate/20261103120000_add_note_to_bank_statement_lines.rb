# frozen_string_literal: true

# Why a bank line was ignored, in the person's words ("swapped a $20 bill
# for $20 on Zelle"), from the sorting mode (Tim, 2026-11-03).
class AddNoteToBankStatementLines < ActiveRecord::Migration[8.1]
  def change
    add_column :bank_statement_lines, :note, :string
  end
end
