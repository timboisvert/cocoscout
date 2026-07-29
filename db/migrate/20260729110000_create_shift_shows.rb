# frozen_string_literal: true

# Explicit shift ↔ show links. A show-based shift covers exactly one show (its
# `source`); this table only holds the extra shows when several are deliberately
# merged into one shift. We never infer covered shows from time anymore.
class CreateShiftShows < ActiveRecord::Migration[8.1]
  def change
    create_table :shift_shows do |t|
      t.references :shift, null: false, foreign_key: true
      t.references :show, null: false, foreign_key: true
      t.timestamps
    end
    add_index :shift_shows, [ :shift_id, :show_id ], unique: true
  end
end
