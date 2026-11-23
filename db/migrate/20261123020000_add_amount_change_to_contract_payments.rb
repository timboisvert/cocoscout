# frozen_string_literal: true

# A manager can change what's owed on a payment and leave a note, down to $0
# for money the organization won't collect (Tim, 2026-11-22: the last $24.00
# of a rehearsal nobody's going to chase). The note, who, when, and the amount
# it was are kept so the row can say what happened and be changed back.
class AddAmountChangeToContractPayments < ActiveRecord::Migration[8.1]
  def change
    add_column :contract_payments, :amount_change_note, :text
    add_column :contract_payments, :amount_changed_at, :datetime
    add_reference :contract_payments, :amount_changed_by, foreign_key: { to_table: :users, on_delete: :nullify }, null: true
    add_column :contract_payments, :amount_before_change, :decimal, precision: 10, scale: 2
  end
end
