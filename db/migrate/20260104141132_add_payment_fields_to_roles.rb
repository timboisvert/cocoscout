class AddPaymentFieldsToRoles < ActiveRecord::Migration[8.1]
  def change
    add_column :roles, :payment_type, :string, default: "non_paying", null: false
    add_column :roles, :payment_amount, :decimal, precision: 10, scale: 2
    add_column :roles, :payment_rate, :decimal, precision: 10, scale: 2
    add_column :roles, :payment_minimum, :decimal, precision: 10, scale: 2
  end
end
