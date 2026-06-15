# frozen_string_literal: true

# Drop the document/handbook distinction — it was only a cosmetic badge with no
# behavioral difference. A handbook is just a document titled accordingly.
class RemoveKindFromProductionDocuments < ActiveRecord::Migration[8.1]
  def change
    remove_column :production_documents, :kind, :integer, default: 0, null: false
  end
end
