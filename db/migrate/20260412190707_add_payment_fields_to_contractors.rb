class AddPaymentFieldsToContractors < ActiveRecord::Migration[8.1]
  def change
    add_column :contractors, :venmo_identifier, :string
    add_column :contractors, :zelle_identifier, :string
  end
end
