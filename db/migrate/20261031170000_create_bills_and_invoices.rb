# frozen_string_literal: true

# Bills (money the organization owes a vendor) and invoices to anyone
# (money owed to the organization outside a contract), Books V1.3 plan
# D1 and D2. Each posts to the books when it's made and again when it's
# paid; part payments are allowed on both.
class CreateBillsAndInvoices < ActiveRecord::Migration[8.0]
  def change
    create_table :bills do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :vendor_name, null: false
      t.string :vendor_email
      t.string :vendor_reference
      t.integer :amount_cents, null: false
      t.date :issued_on, null: false
      t.date :due_on, null: false
      t.string :category_key, null: false
      t.references :production, foreign_key: true
      t.references :show, foreign_key: true
      t.text :memo
      t.string :repeats, null: false, default: "none"
      t.string :status, null: false, default: "open"
      t.integer :paid_cents, null: false, default: 0
      t.date :paid_on
      t.datetime :voided_at
      t.string :void_reason
      t.references :repeated_from, foreign_key: { to_table: :bills }
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :bills, %i[organization_id status due_on]

    create_table :bill_payments do |t|
      t.references :bill, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.date :on, null: false
      t.integer :amount_cents, null: false
      t.string :via, null: false, default: "bank"
      t.string :reference
      t.text :memo
      t.references :recorded_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    create_table :invoices do |t|
      t.references :organization, null: false, foreign_key: true
      t.integer :number, null: false
      t.string :prefix, null: false
      t.string :status, null: false, default: "open"
      t.string :bill_to_name, null: false
      t.string :bill_to_email
      t.string :bill_to_attention
      t.text :bill_to_address
      t.date :issued_on, null: false
      t.date :due_on, null: false
      t.string :category_key, null: false
      t.references :production, foreign_key: true
      t.references :show, foreign_key: true
      t.text :memo
      t.integer :total_cents, null: false, default: 0
      t.integer :paid_cents, null: false, default: 0
      t.date :paid_on
      t.string :payment_token
      t.boolean :pay_by_card, null: false, default: true
      t.boolean :pay_by_bank, null: false, default: true
      t.boolean :pay_by_check, null: false, default: true
      t.string :reminders, null: false, default: "before_and_overdue"
      t.datetime :sent_at
      t.integer :sent_count, null: false, default: 0
      t.datetime :opened_at
      t.datetime :voided_at
      t.string :void_reason
      t.string :stripe_checkout_session_id
      t.string :stripe_payment_intent_id
      t.integer :stripe_fee_cents
      t.datetime :receipt_emailed_at
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :invoices, %i[organization_id number], unique: true
    add_index :invoices, :payment_token, unique: true
    add_index :invoices, %i[organization_id status due_on]

    create_table :invoice_lines do |t|
      t.references :invoice, null: false, foreign_key: true
      t.string :description, null: false
      t.decimal :quantity, precision: 10, scale: 2, null: false, default: 1
      t.integer :unit_cents, null: false, default: 0
      t.integer :amount_cents, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :invoice_payments do |t|
      t.references :invoice, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.date :on, null: false
      t.integer :amount_cents, null: false
      t.string :via, null: false, default: "check"
      t.string :reference
      t.text :memo
      t.references :recorded_by, foreign_key: { to_table: :users }
      t.timestamps
    end
  end
end
