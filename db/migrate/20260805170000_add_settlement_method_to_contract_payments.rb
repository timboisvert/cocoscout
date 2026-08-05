# frozen_string_literal: true

# How an incoming contract payment gets settled: the counterparty pays it
# directly (pay link / recorded payment — the default), or it's deducted from
# their payout when their revenue share is added to a payout run. Makes the old
# display-only "Taken out of their cut" idea real.
class AddSettlementMethodToContractPayments < ActiveRecord::Migration[8.1]
  def change
    add_column :contract_payments, :settlement_method, :string, default: "direct", null: false
  end
end
