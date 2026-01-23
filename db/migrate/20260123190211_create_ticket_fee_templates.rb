class CreateTicketFeeTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :ticket_fee_templates do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.decimal :flat_per_ticket, precision: 10, scale: 4, default: 0
      t.decimal :percentage, precision: 5, scale: 4, default: 0
      t.boolean :is_default, default: false
      t.timestamps
    end

    add_index :ticket_fee_templates, [ :organization_id, :name ], unique: true
  end
end
