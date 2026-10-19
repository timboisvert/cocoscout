# frozen_string_literal: true

# The old per-contract service options: replaced by the organization's
# services (HouseService) on 2026-10-16, every row copied over then. Kept a
# while in case; dropped on Tim's say-so (2026-10-19). Nothing reads it.
class DropContractServiceOptions < ActiveRecord::Migration[8.1]
  def up
    drop_table :contract_service_options
  end

  def down
    create_table :contract_service_options do |t|
      t.bigint :organization_id, null: false
      t.string :name, null: false
      t.integer :default_price_cents, default: 0, null: false
      t.string :unit, default: "flat", null: false
      t.string :default_direction, default: "incoming", null: false
      t.integer :position, default: 0, null: false
      t.string :booking_mode, default: "once", null: false
      t.timestamps
      t.index :organization_id
    end
    add_foreign_key :contract_service_options, :organizations
  end
end
