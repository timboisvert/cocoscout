class CreateContractPayments < ActiveRecord::Migration[8.1]
  def change
    create_table :contract_payments do |t|
      t.references :contract, null: false, foreign_key: true

      # Payment details
      t.string :description
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :direction, null: false # "incoming" (they pay us) or "outgoing" (we pay them)
      t.date :due_date, null: false

      # Payment tracking
      t.string :status, null: false, default: "pending" # pending, paid, overdue, cancelled
      t.date :paid_date
      t.string :payment_method # check, cash, transfer, etc.
      t.string :reference_number # check number, transaction ID, etc.
      t.text :notes

      t.timestamps
    end

    add_index :contract_payments, :status
    add_index :contract_payments, :due_date
    add_index :contract_payments, %i[contract_id status]
  end
end
