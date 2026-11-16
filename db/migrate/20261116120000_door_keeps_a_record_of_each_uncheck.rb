# frozen_string_literal: true

# Unchecking someone at the door (Tim, 2026-11-16): a ticket checked in by
# mistake goes back to valid, and its QR code scans again. Each one is kept
# here, with who checked it in and when, so a ticket checked out and handed
# to someone else shows on its order.
class DoorKeepsARecordOfEachUncheck < ActiveRecord::Migration[8.1]
  def change
    create_table :ticket_unchecks do |t|
      t.references :ticket, null: false, foreign_key: { on_delete: :cascade }
      t.references :ticket_listing, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :unchecked_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :checked_in_at
      t.references :checked_in_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
      t.datetime :created_at, null: false
    end
    add_index :ticket_unchecks, %i[ticket_listing_id created_at]
  end
end
