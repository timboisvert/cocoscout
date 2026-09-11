# frozen_string_literal: true

# Ticket sales split by where the money came from. An org names its sources in
# Money settings (Eventbrite, HotTix, At the door…), and a show's financials
# carry one line per source instead of a single tickets-sold/revenue pair.
#
# show_financials.ticket_count and .ticket_revenue STAY. Around thirty places
# read them — every contract settlement, the per-ticket payout methods, the
# reports — so they become maintained rollups of the lines rather than a second
# thing to enter. A financials row with no lines keeps whatever it already had
# and behaves exactly as before, so nothing needs backfilling.
class AddTicketSourcesAndSalesLines < ActiveRecord::Migration[8.1]
  def change
    create_table :ticket_sources do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :position, default: 0, null: false
      # Archived rather than deleted, so a line sold through a source the org
      # has since stopped using keeps its label.
      t.datetime :archived_at
      t.timestamps
    end
    add_index :ticket_sources, [ :organization_id, :position ]

    create_table :ticket_sales_lines do |t|
      t.references :show_financials, null: false, foreign_key: true
      # Nullable: a line entered before the org named any sources, or one whose
      # source was archived away, still has an amount worth keeping.
      t.references :ticket_source, foreign_key: true
      t.integer :tickets_sold, default: 0, null: false
      t.decimal :amount, precision: 10, scale: 2, default: "0.0", null: false
      t.integer :position, default: 0, null: false
      t.timestamps
    end
    add_index :ticket_sales_lines, [ :show_financials_id, :position ]
  end
end
