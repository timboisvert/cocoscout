# frozen_string_literal: true

# A show canceled, taken away or moved, and who it touched (cast and staff,
# read when it happened, so a deleted show still knows whom it had); then each
# person told about it. docs/show_change_notices_plan.md (Tim, 2026-10-30).
class CreateShowChanges < ActiveRecord::Migration[8.1]
  def change
    create_table :show_changes do |t|
      t.references :organization, null: false, foreign_key: { on_delete: :cascade }
      t.references :production, foreign_key: { on_delete: :nullify }
      t.references :show, foreign_key: { on_delete: :nullify }
      t.references :contract, foreign_key: { on_delete: :nullify }
      t.references :changed_by_user, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :batch, null: false
      t.string :kind, null: false
      t.boolean :booking_only, null: false, default: false
      t.string :show_label, null: false
      t.datetime :was_starts_at
      t.datetime :was_ends_at
      t.datetime :now_starts_at
      t.datetime :now_ends_at
      t.jsonb :cast, null: false, default: []
      t.jsonb :staff, null: false, default: []
      t.datetime :closed_at
      t.timestamps
    end
    add_index :show_changes, :batch
    add_index :show_changes, [ :organization_id, :closed_at ]

    create_table :show_change_notices do |t|
      t.references :show_change, null: false, foreign_key: { on_delete: :cascade }
      t.references :person, null: false, foreign_key: { on_delete: :cascade }
      t.string :audience, null: false
      t.references :sent_by_user, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :show_change_notices, [ :show_change_id, :person_id, :audience ], unique: true, name: "idx_show_change_notices_unique"
  end
end
