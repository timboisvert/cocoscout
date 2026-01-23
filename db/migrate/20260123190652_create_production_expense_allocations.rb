class CreateProductionExpenseAllocations < ActiveRecord::Migration[8.1]
  def change
    create_table :production_expense_allocations do |t|
      t.references :production_expense, null: false, foreign_key: true
      t.references :show, null: false, foreign_key: true
      t.decimal :allocated_amount, precision: 10, scale: 2, null: false
      t.boolean :is_override, default: false
      t.text :override_reason
      t.timestamps
    end

    add_index :production_expense_allocations,
              [ :production_expense_id, :show_id ],
              unique: true,
              name: "idx_prod_exp_alloc_unique"
  end
end
