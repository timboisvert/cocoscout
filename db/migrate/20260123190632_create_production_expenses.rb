class CreateProductionExpenses < ActiveRecord::Migration[8.1]
  def change
    create_table :production_expenses do |t|
      t.references :production, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :category, default: "other"
      t.decimal :total_amount, precision: 10, scale: 2, null: false
      t.date :purchase_date

      # Spread method configuration
      t.string :spread_method, null: false, default: "fixed_months"
      t.integer :spread_months           # For fixed_months
      t.integer :spread_event_count      # For fixed_events
      t.date :spread_start_date
      t.date :spread_end_date
      t.jsonb :selected_show_ids, default: []  # For specific_events
      t.jsonb :event_type_filter, default: []

      # Options
      t.boolean :exclude_non_revenue, default: true
      t.boolean :exclude_canceled, default: true
      t.boolean :active, default: true

      t.timestamps
    end

    add_index :production_expenses, [ :production_id, :active ]
  end
end
