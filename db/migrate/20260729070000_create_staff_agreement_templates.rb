# frozen_string_literal: true

# Reusable employee/staff agreement wording, the staffing analog of
# ContractTemplate. An org keeps one or more named agreements with {{merge_fields}}
# that fill from a staff member's data; staff agree to it during onboarding.
class CreateStaffAgreementTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :staff_agreement_templates do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.string :description
      t.boolean :active, null: false, default: true
      t.integer :version, null: false, default: 1

      t.timestamps
    end
  end
end
