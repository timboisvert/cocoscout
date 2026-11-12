# frozen_string_literal: true

# A category of the organization's own carries a line of what goes in it,
# the way the built-in ones do (Tim, 2026-11-02): the picker shows it
# under the name.
class AddDescriptionToLedgerAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :ledger_accounts, :description, :string
  end
end
