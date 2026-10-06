# frozen_string_literal: true

# An invoice for money someone owes an organization under a contract: one per
# payment, numbered in order per organization (SG-0012). The pay page is the
# invoice; the number is issued the first time anyone opens it.
class CreateContractInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :contract_invoices do |t|
      t.references :organization, null: false, foreign_key: true
      # Nullified when the payment goes away (combined into another, or
      # removed); the invoice stays, void, so its number is never reused.
      t.bigint :contract_payment_id
      t.string :prefix, null: false
      t.integer :number, null: false
      # The payment's pay-link token, kept so an old link to a combined or
      # removed payment can still say what became of it.
      t.string :payment_token
      t.bigint :combined_into_payment_id
      t.datetime :issued_at, null: false
      t.datetime :sent_at
      t.integer :sent_count, null: false, default: 0
      t.datetime :receipt_emailed_at
      t.datetime :voided_at
      t.string :void_reason
      t.timestamps
    end
    add_index :contract_invoices, :contract_payment_id, unique: true
    add_index :contract_invoices, %i[organization_id number], unique: true
    add_index :contract_invoices, :payment_token
    add_foreign_key :contract_invoices, :contract_payments, on_delete: :nullify

    add_column :organizations, :invoice_prefix, :string
    add_column :organizations, :invoice_next_number, :integer, null: false, default: 1
    add_column :organizations, :invoice_details, :jsonb, null: false, default: {}
  end
end
