class CreatePayrollSchedules < ActiveRecord::Migration[8.1]
  def change
    create_table :payroll_schedules do |t|
      t.references :production, null: false, foreign_key: true, index: { unique: true }

      t.string :frequency, null: false, default: "per_show"  # per_show, weekly, biweekly, monthly
      t.integer :pay_day  # For weekly: 0=Sun..6=Sat, for monthly: 1-28
      t.decimal :min_payout_threshold, precision: 10, scale: 2, default: 0
      t.boolean :active, null: false, default: true

      t.timestamps
    end
  end
end
