# frozen_string_literal: true

# Expense reimbursement that rode along in the same external payment — the
# same "Reimbursement" component Pay People records, kept separate from wages
# so year-end statements can tell the two apart. A payment can be
# reimbursement-only (zero hours). Its own migration because the offline
# payment migration had already run in production without this column.
class AddOfflineReimbursementToStaffTimeEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :staff_time_entries, :offline_reimbursement_cents, :bigint
  end
end
