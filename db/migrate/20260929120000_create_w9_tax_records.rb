# frozen_string_literal: true

# Staffing → Taxes, phase 1: W-9 collection.
#
# - organization_tax_settings: the org's payer details (who files the 1099s).
# - w9_submissions: each signed W-9 a person gave an org. History is kept; the
#   newest one without superseded_at is current. TIN/EIN are encrypted by
#   Active Record encryption (text columns — ciphertext is longer than the value).
# - organization_staff_members: request/reminder stamps + a per-person
#   "doesn't need a W-9" flag (mirrors agreement_exempt).
class CreateW9TaxRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :organization_tax_settings do |t|
      t.references :organization, null: false, foreign_key: true, index: { unique: true }
      t.string :legal_name
      t.text :ein
      t.string :ein_last4
      t.string :address_line1
      t.string :address_line2
      t.string :city
      t.string :state
      t.string :zip
      t.string :phone
      t.boolean :w9_required, null: false, default: true
      t.timestamps
    end

    create_table :w9_submissions do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :organization_staff_member, foreign_key: { on_delete: :nullify }
      t.string :legal_name, null: false
      t.string :business_name
      t.string :tax_classification, null: false
      t.string :llc_tax_class
      t.string :other_classification
      t.string :exempt_payee_code
      t.string :fatca_code
      t.string :address_line1, null: false
      t.string :address_line2
      t.string :city, null: false
      t.string :state, null: false
      t.string :zip, null: false
      t.string :tin_type, null: false
      t.text :tin, null: false
      t.string :tin_last4, null: false
      t.boolean :subject_to_backup_withholding, null: false, default: false
      t.string :signature_name, null: false
      t.datetime :signed_at, null: false
      t.string :signed_ip
      t.string :signed_user_agent
      t.string :form_revision, null: false
      t.datetime :e_delivery_consented_at
      t.datetime :superseded_at
      t.timestamps
    end
    add_index :w9_submissions, %i[organization_id person_id],
              unique: true, where: "superseded_at IS NULL", name: "idx_w9_submissions_current"

    # Every time a manager opens a W-9 (which shows the full TIN), we log it.
    # The row outlives the user (nullified) so the trail survives account deletion.
    create_table :tax_document_accesses do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :user, foreign_key: { on_delete: :nullify }
      t.references :w9_submission, null: false, foreign_key: true
      t.string :ip_address
      t.datetime :created_at, null: false
    end

    add_column :organization_staff_members, :w9_requested_at, :datetime
    add_column :organization_staff_members, :w9_last_reminded_at, :datetime
    add_column :organization_staff_members, :tax_form_exempt, :boolean, null: false, default: false
  end
end
