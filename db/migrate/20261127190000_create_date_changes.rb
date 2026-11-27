# frozen_string_literal: true

# A change to one or more dates: canceling them, moving them, deleting them,
# or bringing canceled ones back (Tim, 2026-11-27: "Cancel or move this
# date"). It starts as a draft while the manager goes through the steps
# (which dates, what it touches, review), then keeps the record of what was
# done: each step's progress and anything CocoScout couldn't finish.
class CreateDateChanges < ActiveRecord::Migration[8.1]
  def change
    create_table :date_changes do |t|
      t.references :organization, null: false, foreign_key: { on_delete: :cascade }
      t.references :production, foreign_key: { on_delete: :nullify }
      t.references :show, foreign_key: { on_delete: :nullify }
      t.references :contract, foreign_key: { on_delete: :nullify }
      t.references :contract_date_request, foreign_key: { on_delete: :nullify }
      t.references :created_by_user, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :restores, foreign_key: { to_table: :date_changes, on_delete: :nullify }
      t.string :kind, null: false
      t.string :status, null: false, default: "draft"
      t.string :scope
      t.jsonb :show_ids, null: false, default: []
      t.jsonb :also_show_ids, null: false, default: []
      t.jsonb :move, null: false, default: {}
      t.jsonb :choices, null: false, default: {}
      t.jsonb :steps, null: false, default: []
      t.jsonb :problems, null: false, default: []
      t.jsonb :undo, null: false, default: {}
      t.jsonb :summary, null: false, default: {}
      t.string :batch
      t.datetime :applied_at
      t.timestamps
    end
    add_index :date_changes, %i[organization_id status]
  end
end
