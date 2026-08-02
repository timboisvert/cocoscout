# frozen_string_literal: true

# Tears down the last of the abandoned Solid Cable experiment. The adapter was
# never used (dev = async, prod = redis), so this table only ever sat empty in
# the shared database. if_exists keeps a fresh setup (where the table was never
# created) a safe no-op.
class DropSolidCableMessages < ActiveRecord::Migration[8.1]
  def up
    drop_table :solid_cable_messages, if_exists: true
  end

  def down
    # Solid Cable is gone — nothing to recreate.
  end
end
