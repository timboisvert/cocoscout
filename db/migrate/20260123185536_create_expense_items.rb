class CreateExpenseItems < ActiveRecord::Migration[8.1]
  def change
    create_table :expense_items do |t|
      t.references :show_financials, null: false, foreign_key: true
      t.string :category, null: false, default: 'other'
      t.string :description
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.integer :position, default: 0
      t.timestamps
    end

    add_index :expense_items, [ :show_financials_id, :position ]
  end
end
