class CreateContractDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :contract_documents do |t|
      t.references :contract, null: false, foreign_key: true
      t.string :name, null: false
      t.string :document_type # signed_contract, rider, invoice, etc.
      t.text :notes

      t.timestamps
    end
  end
end
