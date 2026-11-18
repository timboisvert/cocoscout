# frozen_string_literal: true

# Through a connected contract, the contractor's organization chooses who
# on its side is notified as tickets sell and comps are given at the
# organization that sells them (Tim, 2026-11-17). One row per person per
# connection; each person can switch theirs off in their own account.
class PeopleCanBeNotifiedOfAConnectedContractsTicketSales < ActiveRecord::Migration[8.1]
  def up
    create_table :contract_connection_watchers do |t|
      t.references :contract_connection, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :enabled_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
      # When the person switched it off for themself; nil while it's on.
      t.datetime :muted_at
      t.timestamps
    end
    add_index :contract_connection_watchers, %i[contract_connection_id user_id], unique: true, name: "index_connection_watchers_one_per_person"
    ContractConnectionTemplates.ensure!
  end

  def down
    drop_table :contract_connection_watchers
  end
end
