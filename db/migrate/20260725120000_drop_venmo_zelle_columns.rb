# frozen_string_literal: true

# Everyone is now paid on the Stripe rail (payout runs), with cash/check kept only
# for manual/historical reconciliation. The Venmo/Zelle identifier columns are no
# longer read or written anywhere, so drop them across every payee table.
class DropVenmoZelleColumns < ActiveRecord::Migration[8.1]
  def change
    # Talent
    remove_column :people, :venmo_identifier, :string
    remove_column :people, :venmo_identifier_type, :string
    remove_column :people, :venmo_verified_at, :datetime
    remove_column :people, :zelle_identifier, :string
    remove_column :people, :zelle_identifier_type, :string
    remove_column :people, :zelle_verified_at, :datetime
    remove_column :people, :preferred_payment_method, :string

    # Groups (Venmo only)
    remove_column :groups, :venmo_identifier, :string
    remove_column :groups, :venmo_identifier_type, :string
    remove_column :groups, :venmo_verified_at, :datetime

    # Contractors (identifier only, no type)
    remove_column :contractors, :venmo_identifier, :string
    remove_column :contractors, :zelle_identifier, :string

    # Organizations
    remove_column :organizations, :venmo_identifier, :string
    remove_column :organizations, :zelle_identifier, :string
    remove_column :organizations, :preferred_payment_method, :string

    # Guest payout line items
    remove_column :show_payout_line_items, :guest_venmo, :string
    remove_column :show_payout_line_items, :guest_zelle, :string
  end
end
