# frozen_string_literal: true

# A sorting pass over the bank lines waiting (Books → Bank → Sort), one per
# person and organization: how many were waiting when it started, rules
# made, and what was skipped. It lived in the session cookie for a day and
# outgrew it (70 skipped payees passed 4KB; the browser dropped the cookie).
class CreateBankSortPasses < ActiveRecord::Migration[8.1]
  def change
    create_table :bank_sort_passes do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :total, null: false, default: 0
      t.integer :rules_made, null: false, default: 0
      t.string :skipped_payees, array: true, null: false, default: []
      t.bigint :skipped_lines, array: true, null: false, default: []
      t.boolean :revisited, null: false, default: false
      t.timestamps
    end
    add_index :bank_sort_passes, [ :organization_id, :user_id ], unique: true
  end
end
