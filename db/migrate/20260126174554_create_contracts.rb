class CreateContracts < ActiveRecord::Migration[8.1]
  def change
    create_table :contracts do |t|
      t.references :organization, null: false, foreign_key: true

      # Contractor info
      t.string :contractor_name, null: false
      t.string :contractor_email
      t.string :contractor_phone
      t.text :contractor_address

      # Status tracking
      t.string :status, null: false, default: "draft"
      t.datetime :activated_at
      t.datetime :completed_at
      t.datetime :cancelled_at

      # Draft data storage (JSON blob for wizard state before activation)
      t.jsonb :draft_data, default: {}

      # Contract terms
      t.text :notes
      t.text :terms
      t.date :contract_start_date
      t.date :contract_end_date

      t.timestamps
    end

    add_index :contracts, :status
    add_index :contracts, %i[organization_id status]
  end
end
