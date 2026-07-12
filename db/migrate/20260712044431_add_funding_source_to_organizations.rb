class AddFundingSourceToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :funding_payment_method_id, :string
    add_column :organizations, :funding_payment_method_label, :string
    add_column :organizations, :funding_payment_method_type, :string
  end
end
