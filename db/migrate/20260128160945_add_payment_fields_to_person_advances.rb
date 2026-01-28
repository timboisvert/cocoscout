class AddPaymentFieldsToPersonAdvances < ActiveRecord::Migration[8.1]
  def change
    add_column :person_advances, :paid_at, :datetime
    add_column :person_advances, :payment_method, :string
    add_reference :person_advances, :paid_by, null: true, foreign_key: { to_table: :users }
  end
end
