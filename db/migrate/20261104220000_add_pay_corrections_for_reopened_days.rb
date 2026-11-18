# frozen_string_literal: true

# A Settle up day reopened after its money was paid (Tim, 2026-11-04: paid
# means the payout run was submitted). What was paid stays as it was paid,
# and the difference is carried beside it:
#   a performer's line   a correction line for the same person on the same
#                        show (more owed rides the next run; overpaid is a
#                        negative line the payee ledger nets out of their
#                        next pay)
#   a tip share          remembers what was paid, so the share can follow the
#                        day and the difference waits on Pay People
class AddPayCorrectionsForReopenedDays < ActiveRecord::Migration[8.0]
  def change
    add_reference :show_payout_line_items, :correction_of, foreign_key: { to_table: :show_payout_line_items, on_delete: :nullify }, index: true
    remove_index :show_payout_line_items, name: "idx_payout_line_items_unique_payee"
    add_index :show_payout_line_items, %i[show_payout_id payee_type payee_id is_individual_allocation],
              name: "idx_payout_line_items_unique_payee", unique: true, where: "correction_of_id IS NULL"
    add_column :tip_shares, :paid_cents, :integer
  end
end
