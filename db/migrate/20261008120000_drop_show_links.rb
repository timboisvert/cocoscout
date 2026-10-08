# frozen_string_literal: true

# Show links are gone (Tim, 2026-10-08: unused; a date's ticket link lives on
# its Tickets tab, and its notes stay).
class DropShowLinks < ActiveRecord::Migration[8.1]
  def up
    drop_table :show_links
  end

  def down
    create_table :show_links do |t|
      t.bigint :show_id, null: false
      t.string :text
      t.string :url, null: false
      t.timestamps
    end
    add_index :show_links, :show_id
    add_foreign_key :show_links, :shows
  end
end
