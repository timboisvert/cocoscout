# frozen_string_literal: true

# The production <-> contract relationship was inverted (a contract now belongs_to
# a production; a production has_many contracts). The legacy productions.contract_id
# column was kept temporarily for rollback safety and is now unused — drop it.
class RemoveContractIdFromProductions < ActiveRecord::Migration[8.1]
  def up
    remove_reference :productions, :contract, foreign_key: true, index: true
  end

  def down
    add_reference :productions, :contract, foreign_key: true, index: true, null: true
  end
end
