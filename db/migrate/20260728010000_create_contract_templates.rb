# frozen_string_literal: true

# Reusable contract documents (the legal wording), mirroring AgreementTemplate.
# An org keeps a few named templates ("Rental Agreement", "Performer Deal") whose
# {{merge_fields}} get filled from a contract's data when it's sent for signature.
# Versioned: signatures snapshot the exact content signed, so bumping a template
# never rewrites history.
class CreateContractTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :contract_templates do |t|
      t.string :name, null: false
      t.text :description
      t.boolean :active, null: false, default: true
      t.integer :version, null: false, default: 1
      t.references :organization, null: false, foreign_key: true

      t.timestamps
    end
    add_index :contract_templates, [ :organization_id, :active ]

    # Which template rendered a given contract's document (nullable — offline
    # contracts never pick one).
    add_reference :contracts, :contract_template, null: true, foreign_key: true
  end
end
