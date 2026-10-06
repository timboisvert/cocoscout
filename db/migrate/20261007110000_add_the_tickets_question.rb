# frozen_string_literal: true

# The Tickets question (Tim, 2026-10-06): every production is asked once
# where people get tickets. Sell them on CocoScout, somewhere else (a link),
# or no tickets. A date can point somewhere else than its production. A
# production already selling on CocoScout has answered.
class AddTheTicketsQuestion < ActiveRecord::Migration[8.1]
  def up
    add_column :productions, :tickets_mode, :string, default: "unset", null: false
    add_column :productions, :tickets_url, :string
    add_column :shows, :tickets_url, :string
    add_column :production_ticketings, :excluded_show_ids, :jsonb, default: [], null: false
    execute <<~SQL
      UPDATE productions SET tickets_mode = 'cocoscout'
      WHERE id IN (SELECT production_id FROM production_ticketings WHERE enabled)
    SQL
  end

  def down
    remove_column :productions, :tickets_mode
    remove_column :productions, :tickets_url
    remove_column :shows, :tickets_url
    remove_column :production_ticketings, :excluded_show_ids
  end
end
