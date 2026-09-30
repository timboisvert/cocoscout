# frozen_string_literal: true

# One payout run for everything: staff pay now shares the run with performers,
# course money and contract payments, so what a line is (and how it settles)
# moves from the run's kind down to the line. Staff lines are "staffing" (paid
# as the literal grid amount); everything else is "performer" (netted against
# the performer ledger, advances included).
#
# A person paid for both in one run gets one transfer that posts TWO payout
# ledger entries (one per category) sourced on the same item — so the ledger's
# idempotency key widens to include the category.
class AddCategoryToPayoutContributions < ActiveRecord::Migration[8.1]
  def up
    add_column :payout_contributions, :category, :string, null: false, default: "performer"

    execute <<~SQL
      UPDATE payout_contributions
         SET category = 'staffing'
        FROM payout_batches
       WHERE payout_batches.id = payout_contributions.payout_batch_id
         AND payout_batches.kind = 'staff_pay'
    SQL

    remove_index :payout_ledger_entries, name: "index_payout_ledger_entries_on_source_and_type"
    add_index :payout_ledger_entries, %i[source_type source_id entry_type category],
              unique: true, where: "source_id IS NOT NULL",
              name: "index_payout_ledger_entries_on_source_type_and_category"
  end

  def down
    remove_index :payout_ledger_entries, name: "index_payout_ledger_entries_on_source_type_and_category"
    add_index :payout_ledger_entries, %i[source_type source_id entry_type],
              unique: true, where: "source_id IS NOT NULL",
              name: "index_payout_ledger_entries_on_source_and_type"
    remove_column :payout_contributions, :category
  end
end
