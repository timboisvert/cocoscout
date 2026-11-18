# frozen_string_literal: true

# A production's ticket page at its own address (Tim, 2026-11-09): blank is
# the production's public URL, as before. The addresses it used to have keep
# landing on it.
class TicketPagesCanHaveTheirOwnAddress < ActiveRecord::Migration[8.1]
  def change
    add_column :production_ticketings, :page_key, :string
    add_column :production_ticketings, :old_page_keys, :jsonb, default: [], null: false
    add_index :production_ticketings, %i[organization_id page_key], unique: true, where: "page_key IS NOT NULL",
              name: "index_production_ticketings_on_org_and_page_key"
  end
end
