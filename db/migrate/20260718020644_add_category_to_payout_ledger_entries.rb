# frozen_string_literal: true

# Scope each ledger entry to a run kind so a run can pay a payee's *net owed
# within that scope* (e.g. a performer run pays performer + contractor + advance
# balances, not someone's unpaid staff pay). Backfill staffing entries by their
# source's batch; everything else is performer.
class AddCategoryToPayoutLedgerEntries < ActiveRecord::Migration[8.1]
  def up
    add_column :payout_ledger_entries, :category, :string, null: false, default: "performer"
    add_index :payout_ledger_entries, [ :payee_type, :payee_id, :category ], name: "idx_ledger_entries_on_payee_and_category"

    staff_batch_ids = PayoutBatch.where(kind: "staff_pay").pluck(:id)
    if staff_batch_ids.any?
      staff_contribution_ids = PayoutContribution.where(payout_batch_id: staff_batch_ids).pluck(:id)
      staff_item_ids = PayoutBatchItem.where(payout_batch_id: staff_batch_ids).pluck(:id)
      PayoutLedgerEntry.where(source_type: "PayoutContribution", source_id: staff_contribution_ids).update_all(category: "staffing")
      PayoutLedgerEntry.where(source_type: "PayoutBatchItem", source_id: staff_item_ids).update_all(category: "staffing")
    end
  end

  def down
    remove_column :payout_ledger_entries, :category
  end
end
