# frozen_string_literal: true

# A contract settlement that was already paid when its day was reopened
# (Tim, 2026-11-04) stays as it was paid; the difference from what the show
# now owes is a payment of its own on the contract, pointing back at it:
# more owed is an outgoing payment that rides the next run, overpaid is a
# charge netted out of their next share.
class AddCorrectionOfToContractPayments < ActiveRecord::Migration[8.0]
  def change
    add_reference :contract_payments, :correction_of, foreign_key: { to_table: :contract_payments, on_delete: :nullify }, index: true
  end
end
