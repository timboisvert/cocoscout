class AddPaymentFieldsToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :venmo_identifier, :string
    add_column :organizations, :zelle_identifier, :string
    add_column :organizations, :preferred_payment_method, :string
  end
end
