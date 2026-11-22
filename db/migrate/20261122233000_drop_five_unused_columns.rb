# frozen_string_literal: true

# Step 2 of dropping five columns nothing uses (Tim, 2026-11-22). Step 1
# (32737e21) set them ignored and is deployed; after this deploys, the
# ignored_columns lines in User and TaxRate go.
class DropFiveUnusedColumns < ActiveRecord::Migration[8.1]
  def change
    remove_column :users, :invitation_sent_at, :datetime
    remove_column :users, :last_message_digest_sent_at, :datetime
    remove_column :tax_rates, :applies_to_fees, :boolean, default: false, null: false
    remove_column :tax_rates, :registration_number, :string
    remove_column :tax_rates, :effective_to, :date
  end
end
