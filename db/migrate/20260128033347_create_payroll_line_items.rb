class CreatePayrollLineItems < ActiveRecord::Migration[8.1]
  def change
    create_table :payroll_line_items do |t|
      t.references :payroll_run, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true

      t.decimal :gross_amount, precision: 10, scale: 2, null: false, default: 0
      t.decimal :advance_deductions, precision: 10, scale: 2, null: false, default: 0
      t.decimal :net_amount, precision: 10, scale: 2, null: false, default: 0
      t.integer :show_count, default: 0
      t.jsonb :breakdown, default: {}  # Details of included shows

      # Payment tracking (same as ShowPayoutLineItem)
      t.boolean :manually_paid, default: false
      t.datetime :manually_paid_at
      t.references :manually_paid_by, null: true, foreign_key: { to_table: :users }
      t.string :payment_method
      t.text :payment_notes
      t.datetime :paid_at

      # Automated payout tracking
      t.string :payout_reference_id
      t.string :payout_status
      t.text :payout_error

      t.timestamps
    end

    add_index :payroll_line_items, [ :payroll_run_id, :person_id ], unique: true
  end
end
