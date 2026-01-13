class AddZelleFieldsToPeople < ActiveRecord::Migration[8.1]
  def change
    add_column :people, :zelle_identifier, :string
    add_column :people, :zelle_identifier_type, :string
    add_column :people, :zelle_verified_at, :datetime
    add_column :people, :preferred_payment_method, :string
  end
end
