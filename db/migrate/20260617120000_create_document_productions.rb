# frozen_string_literal: true

# A document can apply to more than one production (e.g. a performer handbook
# shared by two shows). The document keeps its primary `production_id` as its
# "home", and this join lists every production it applies to (including the
# primary). One handbook, many productions, edited once.
class CreateDocumentProductions < ActiveRecord::Migration[8.1]
  def up
    create_table :document_productions do |t|
      t.references :production_document, null: false, foreign_key: true
      t.references :production, null: false, foreign_key: true
      t.timestamps
    end
    add_index :document_productions, [ :production_document_id, :production_id ],
              unique: true, name: "idx_document_productions_unique"

    # Backfill: every existing document applies to its current production.
    execute <<~SQL.squish
      INSERT INTO document_productions (production_document_id, production_id, created_at, updated_at)
      SELECT id, production_id, NOW(), NOW() FROM production_documents
    SQL
  end

  def down
    drop_table :document_productions
  end
end
