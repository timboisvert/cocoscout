class CreatePayrollRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :payroll_runs do |t|
      t.references :production, null: false, foreign_key: true
      t.references :payroll_schedule, null: true, foreign_key: true  # Nullable for ad-hoc runs
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.references :processed_by, null: true, foreign_key: { to_table: :users }

      t.date :period_start, null: false
      t.date :period_end, null: false
      t.string :status, null: false, default: "pending"  # pending, processing, completed, cancelled
      t.decimal :total_amount, precision: 10, scale: 2, default: 0
      t.integer :line_item_count, default: 0
      t.datetime :processed_at
      t.text :notes

      t.timestamps
    end

    add_index :payroll_runs, [ :production_id, :period_start, :period_end ]
    add_index :payroll_runs, :status
  end
end
