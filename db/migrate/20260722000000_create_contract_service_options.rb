# frozen_string_literal: true

# An organization's catalog of services it can offer on contracts (technical
# services, booth tech, etc.) with default prices. Each contract draws from this
# list and can add/override. Managed on the Contract Settings page.
class CreateContractServiceOptions < ActiveRecord::Migration[8.1]
  def change
    create_table :contract_service_options do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :default_price_cents, null: false, default: 0
      t.string :unit, null: false, default: "flat"            # flat | hourly
      t.string :default_direction, null: false, default: "incoming" # incoming (they pay us) | outgoing (we pay them)
      t.integer :position, null: false, default: 0
      t.timestamps
    end
  end
end
