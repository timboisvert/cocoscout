# frozen_string_literal: true

class CreateCourseOfferingPayouts < ActiveRecord::Migration[8.1]
  def change
    create_table :course_offering_payouts do |t|
      t.references :course_offering, null: false, foreign_key: true, index: { unique: true }
      t.string :payout_mode, default: "lump_sum", null: false
      t.integer :total_revenue_cents
      t.integer :total_revenue_override_cents
      t.integer :platform_fee_cents
      t.integer :net_revenue_cents
      t.integer :total_payout_cents
      t.string :status, default: "pending", null: false
      t.datetime :calculated_at
      t.datetime :paid_at
      t.text :notes

      t.timestamps
    end

    add_index :course_offering_payouts, :status

    create_table :course_offering_payout_line_items do |t|
      t.references :course_offering_payout, null: false, foreign_key: true
      t.string :payee_type
      t.bigint :payee_id
      t.integer :amount_cents, null: false
      t.string :label
      t.jsonb :calculation_details, default: {}
      t.boolean :manually_paid, default: false, null: false
      t.datetime :manually_paid_at
      t.references :manually_paid_by, foreign_key: { to_table: :users }
      t.string :payment_method
      t.text :payment_notes
      t.datetime :paid_at

      t.timestamps
    end

    add_index :course_offering_payout_line_items, [ :payee_type, :payee_id ], name: "idx_course_payout_line_items_payee"

    add_reference :course_offerings, :created_by_user, foreign_key: { to_table: :users }, null: true
  end
end
