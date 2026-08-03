# frozen_string_literal: true

# Hours can be settled outside CocoScout (e.g. a payroll check cut before the
# org moved staff pay onto the platform). A manager marks the entry "already
# paid" from the Approve Hours queue: it counts as paid — never pullable into a
# pay run — without a payout batch behind it.
class AddOfflinePaymentToStaffTimeEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :staff_time_entries, :offline_paid_at, :datetime
    add_column :staff_time_entries, :offline_paid_by_id, :bigint
    add_column :staff_time_entries, :offline_payment_note, :string
    # What the external system actually paid for these hours. Role rates drift
    # over time, so historical imports (e.g. Gusto) record the true dollars
    # rather than re-pricing old hours at today's rate. Nil = price by rate.
    add_column :staff_time_entries, :offline_amount_cents, :bigint

    add_index :staff_time_entries, :offline_paid_by_id
    add_foreign_key :staff_time_entries, :users, column: :offline_paid_by_id
  end
end
