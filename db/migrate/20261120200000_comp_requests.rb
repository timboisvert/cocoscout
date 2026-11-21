# frozen_string_literal: true

# Requesting more comps for one date (Tim, 2026-11-20): whether production
# team managers and contractors may request more (on the box office, a
# production and a date, like the rest of the comp rules), and the requests.
class CompRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :ticketing_profiles, :team_comp_requests, :boolean, default: false, null: false
    add_column :ticketing_profiles, :contract_comp_requests, :boolean, default: false, null: false
    # A production's or a date's own comp rules; nil while it follows the level above.
    add_column :production_ticketings, :team_comp_requests, :boolean
    add_column :production_ticketings, :contract_comp_requests, :boolean
    add_column :ticket_listings, :team_comp_requests, :boolean
    add_column :ticket_listings, :contract_comp_requests, :boolean

    create_table :comp_requests do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :ticket_listing, null: false, foreign_key: true
      # team: a production's team managers; contract: everyone on the contract's side.
      t.string :side, null: false
      t.references :requested_by, null: false, foreign_key: { to_table: :users }
      t.integer :quantity, null: false
      t.text :note
      # waiting, approved, declined, withdrawn, closed
      t.string :status, null: false, default: "waiting"
      t.integer :approved_quantity
      t.references :decided_by, foreign_key: { to_table: :users }
      t.datetime :decided_at
      t.text :comment
      # Why a request closed without a decision: showtime, turned_off.
      t.string :closed_reason
      t.timestamps
    end
    add_index :comp_requests, %i[ticket_listing_id side], unique: true, where: "status = 'waiting'", name: "index_comp_requests_one_waiting_per_side"
  end
end
