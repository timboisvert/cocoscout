# frozen_string_literal: true

# A payment can carry service charges folded into it ("Oct 10 event $350 incl.
# Booth Tech $50" is ONE $400 payment). components records what was folded, so
# an amendment can unfold and re-bill without guessing from the description.
class AddComponentsToContractPayments < ActiveRecord::Migration[8.1]
  def change
    add_column :contract_payments, :components, :jsonb, default: [], null: false
  end
end
