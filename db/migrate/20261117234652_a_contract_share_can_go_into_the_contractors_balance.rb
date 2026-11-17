# frozen_string_literal: true

# A connected contract's share can be paid into the contractor's own
# organization's CocoScout balance, in place of the contractor's bank (Tim,
# 2026-11-17). The contractor chooses, per connection. With the words of the
# notices about the choice and about a share arriving.
class AContractShareCanGoIntoTheContractorsBalance < ActiveRecord::Migration[8.1]
  def up
    add_column :contract_connections, :pay_into_balance, :boolean, null: false, default: false
    add_column :contract_connections, :pay_choice_at, :datetime
    add_reference :contract_connections, :pay_choice_by, foreign_key: { to_table: :users, on_delete: :nullify }
    ContractConnectionTemplates.ensure!
  end

  def down
    remove_reference :contract_connections, :pay_choice_by
    remove_column :contract_connections, :pay_choice_at
    remove_column :contract_connections, :pay_into_balance
  end
end
