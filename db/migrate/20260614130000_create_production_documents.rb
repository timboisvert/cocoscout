# frozen_string_literal: true

# Per-production rich-text documents & handbooks, editable in-app and
# optionally shared with the cast. Replaces the single "Production Notes" blob.
class CreateProductionDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :production_documents do |t|
      t.references :production, null: false, foreign_key: true
      t.string :title, null: false
      t.integer :kind, default: 0, null: false        # 0 = document, 1 = handbook
      t.boolean :visible_to_cast, default: true, null: false
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index :production_documents, [ :production_id, :position ]
  end
end
