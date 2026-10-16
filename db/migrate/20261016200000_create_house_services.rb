# frozen_string_literal: true

# Services a show needs (after-V1 #6, Tim 2026-10-16): the organization's own
# list of what it offers productions (booth tech, ticket taking, a projector),
# the roles that do each, what a production's shows need, and the shows that
# differ. Replaces Contract Settings' catalog (contract_service_options, kept
# until the retrofit has copied it; dropped next release).
class CreateHouseServices < ActiveRecord::Migration[8.1]
  def change
    create_table :house_services do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :default_price_cents, null: false, default: 0
      t.string :unit, null: false, default: "flat"
      t.integer :position, null: false, default: 0
      # Contract Settings → Services: offered on contracts, and its usual terms
      # there. A blank contract price means the default price.
      t.boolean :offered_on_contracts, null: false, default: false
      t.integer :contract_price_cents
      t.string :contract_direction, null: false, default: "incoming"
      t.string :contract_booking_mode, null: false, default: "once"
      t.timestamps
    end
    add_index :house_services, "organization_id, lower(name)", unique: true, name: "index_house_services_on_org_and_name"

    create_table :house_service_roles do |t|
      t.references :house_service, null: false, foreign_key: true
      t.references :house_role, null: false, foreign_key: true
      t.timestamps
    end
    add_index :house_service_roles, %i[house_service_id house_role_id], unique: true, name: "index_house_service_roles_unique"

    create_table :production_service_needs do |t|
      t.references :production, null: false, foreign_key: true
      t.references :house_service, null: false, foreign_key: true
      t.integer :people_count, null: false, default: 1
      t.timestamps
    end
    add_index :production_service_needs, %i[production_id house_service_id], unique: true, name: "index_production_service_needs_unique"

    # One show differing from its production: needed false drops a service it
    # would otherwise get; needed true adds one (or changes how many people).
    create_table :show_service_changes do |t|
      t.references :show, null: false, foreign_key: true
      t.references :house_service, null: false, foreign_key: true
      t.boolean :needed, null: false, default: true
      t.integer :people_count, null: false, default: 1
      t.timestamps
    end
    add_index :show_service_changes, %i[show_id house_service_id], unique: true, name: "index_show_service_changes_unique"
  end
end
