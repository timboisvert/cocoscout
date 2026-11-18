# frozen_string_literal: true

# One show, two organizations (Tim, 2026-11-14 to 17): a contract can be
# connected to the contractor's own organization on CocoScout. The
# contractor requests it, the organization that wrote the contract accepts,
# and from then on the contract's dates appear in a production of the
# contractor's organization, with their ticket sales read-only.
#
# A connection is the request and its answer. Each of the contractor's dates
# that follows one of the contract's carries linked_show_id.
class ContractsCanConnectToTheContractorsOrganization < ActiveRecord::Migration[8.1]
  def change
    create_table :contract_connections do |t|
      # The organization that wrote the contract.
      t.references :organization, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :contract, null: false, foreign_key: { on_delete: :cascade }, index: false
      # The contractor's own organization, and the production there that
      # takes the contract's dates. No production yet when they asked for a
      # new one made from the contract: it's made on accepting.
      t.references :linked_organization, null: false, foreign_key: { to_table: :organizations, on_delete: :cascade }
      t.references :linked_production, foreign_key: { to_table: :productions, on_delete: :nullify }
      t.string :new_production_name
      t.string :status, null: false, default: "requested"
      t.references :requested_by, null: false, foreign_key: { to_table: :users, on_delete: :cascade }, index: false
      t.text :note
      t.references :answered_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
      t.datetime :answered_at
      t.text :answer_note
      # How far the yes goes for later contracts with this contractor:
      # "ask" each time, later contracts for this "production", or "all".
      t.string :later_contracts, null: false, default: "ask"
      # What they said about dates already in their production when they
      # asked: { "<contract show id>" => "<their show id>" | "new" }, and
      # "unsure" => [ their show ids left as a question ].
      t.jsonb :date_answers, null: false, default: {}
      # Who in the contractor's organization sees the ticket sales, below
      # its owners and managers: the box office's three choices.
      t.string :team_manager_sales, null: false, default: "everything"
      t.string :team_viewer_sales, null: false, default: "numbers"
      t.string :cast_sales, null: false, default: "production_cast"
      t.references :ended_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
      t.datetime :ended_at
      # When the contractor cleared a "declined" or "unlinked" from their page.
      t.datetime :dismissed_at
      t.timestamps
    end
    add_index :contract_connections, %i[organization_id status]
    # One live connection (requested or connected) per contract.
    add_index :contract_connections, :contract_id, unique: true, where: "status IN ('requested', 'connected')",
              name: "index_contract_connections_one_live_per_contract"
    add_index :contract_connections, :contract_id, name: "index_contract_connections_on_contract_id"

    # A date in the contractor's production that follows one of the
    # contract's: its time and place are that show's.
    add_reference :shows, :linked_show, foreign_key: { to_table: :shows, on_delete: :nullify }
  end
end
