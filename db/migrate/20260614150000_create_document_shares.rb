# frozen_string_literal: true

# Audience grants for production documents. A document is visible to a person if
# ANY share matches them: team / cast (production-scoped, audience_id null),
# talent_pool (audience_id = talent_pool id), or person (audience_id = person id).
# Replaces the single visible_to_cast boolean.
class CreateDocumentShares < ActiveRecord::Migration[8.1]
  def up
    create_table :document_shares do |t|
      t.references :production_document, null: false, foreign_key: true
      t.string :audience_type, null: false
      t.bigint :audience_id
      t.timestamps
    end
    add_index :document_shares, [ :audience_type, :audience_id ]

    # Migrate existing docs: cast-visible -> a 'cast' grant, otherwise 'team'.
    execute <<~SQL.squish
      INSERT INTO document_shares (production_document_id, audience_type, created_at, updated_at)
      SELECT id, CASE WHEN visible_to_cast THEN 'cast' ELSE 'team' END, NOW(), NOW()
      FROM production_documents
    SQL

    remove_column :production_documents, :visible_to_cast
  end

  def down
    add_column :production_documents, :visible_to_cast, :boolean, default: true, null: false
    execute <<~SQL.squish
      UPDATE production_documents SET visible_to_cast = TRUE
      WHERE id IN (SELECT production_document_id FROM document_shares WHERE audience_type = 'cast')
    SQL
    drop_table :document_shares
  end
end
