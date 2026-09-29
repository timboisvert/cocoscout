# frozen_string_literal: true

# Phase 2 of Staffing → Taxes: the 1099-NEC records themselves.
#
# One row per (org, person, tax year, revision). A generated "draft" carries
# the computed year total (`nec_box1_cents`) and a snapshot of the recipient's
# details from the W-9 that was current on generation day. Amount and address
# are editable by the payer up until the form is delivered — after that, a
# correction (a new row pointing back at this one via corrects_id) is the way.
class CreateTaxForm1099s < ActiveRecord::Migration[8.1]
  def change
    create_table :tax_form_1099s do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :w9_submission, foreign_key: { on_delete: :nullify }
      t.integer :tax_year, null: false
      t.bigint :nec_box1_cents, null: false, default: 0
      t.bigint :federal_withheld_cents, null: false, default: 0
      # A one-off adjustment (positive or negative cents) for money the payer
      # settled outside CocoScout entirely — with a note explaining why.
      t.bigint :adjustment_cents, null: false, default: 0
      t.string :adjustment_note

      t.string :status, null: false, default: "draft"

      # Snapshot of the recipient's W-9 details, frozen at generation time so a
      # W-9 update later doesn't re-shape a form already sent.
      t.string :recipient_name, null: false
      t.string :recipient_business_name
      t.string :recipient_tin_type, null: false
      t.string :recipient_tin_last4, null: false
      t.string :recipient_address_line1, null: false
      t.string :recipient_address_line2
      t.string :recipient_city, null: false
      t.string :recipient_state, null: false
      t.string :recipient_zip, null: false
      t.boolean :recipient_e_delivery_consented, null: false, default: false

      # Snapshot of the payer's details from OrganizationTaxSetting at generation.
      t.string :payer_name, null: false
      t.string :payer_ein_last4, null: false
      t.string :payer_address_line1, null: false
      t.string :payer_address_line2
      t.string :payer_city, null: false
      t.string :payer_state, null: false
      t.string :payer_zip, null: false
      t.string :payer_phone

      t.datetime :delivered_at
      t.datetime :filed_at
      t.string :filing_reference
      # Notes the manager adds on marking filed ("uploaded to IRIS 2027-01-25").
      t.text :filing_notes

      t.references :corrects, foreign_key: { to_table: :tax_form_1099s, on_delete: :nullify }
      t.references :generated_by, foreign_key: { to_table: :users, on_delete: :nullify }

      t.timestamps
    end

    add_index :tax_form_1099s, %i[organization_id tax_year status]
    add_index :tax_form_1099s, %i[person_id tax_year]
  end
end
