# frozen_string_literal: true

# Signature requests used to sit open forever. Now they carry a deadline, get
# chased, and expire — and if we're going to tell someone a contract must be
# signed by a date, that date has to actually mean something.
class AddSignatureDeadlines < ActiveRecord::Migration[8.1]
  def change
    # 7, 14 or 30 days. Not nullable — every request gets a deadline.
    add_column :organizations, :signature_expiry_days, :integer, null: false, default: 14

    add_column :contract_versions, :signature_due_at, :datetime
    add_column :contract_versions, :last_nudged_at, :datetime
    add_column :contract_versions, :nudge_count, :integer, null: false, default: 0
    add_column :contract_versions, :expired_at, :datetime

    add_index :contract_versions, :signature_due_at
  end
end
