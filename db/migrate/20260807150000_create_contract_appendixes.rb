# frozen_string_literal: true

# Appendixes: titled rich-text sections that live at the end of the contract
# body, above the signatures, and are part of what gets signed. A tech rider or
# hospitality list belongs to one deal, so they're per-contract rather than
# per-template.
class CreateContractAppendixes < ActiveRecord::Migration[8.1]
  def change
    create_table :contract_appendixes do |t|
      t.references :contract, null: false, foreign_key: true
      t.string :title, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :contract_appendixes, [ :contract_id, :position ]

    # Per-version PDFs: keeps v1's document downloadable forever.
    add_reference :contract_documents, :contract_version, foreign_key: true
  end
end
