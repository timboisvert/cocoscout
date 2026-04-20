# frozen_string_literal: true

class CreateOrgPayouts < ActiveRecord::Migration[8.1]
  def change
    create_table :org_payouts do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :course_offering, null: true, foreign_key: true
      t.integer :amount_cents, null: false
      t.string :payment_method, null: false
      t.string :status, default: "pending", null: false
      t.datetime :paid_at
      t.references :paid_by_user, foreign_key: { to_table: :users }, null: true
      t.text :notes
      t.string :payout_type, default: "custom", null: false
      t.jsonb :covers_sessions, default: []

      t.timestamps
    end

    add_index :org_payouts, :status
    add_index :org_payouts, :payout_type
  end
end
