# frozen_string_literal: true

# Emails to followers beyond the 500 a month Pro includes (Tim, 2026-11-17):
# an organization buys a block of 1,000 for $3 when a send needs it. The
# month's 500 are used first and don't carry over; what a block paid for
# does. Each block goes on the organization's next monthly bill. A sent
# email remembers how many of its emails came out of paid blocks.
class OrganizationsCanBuyMoreFollowerEmails < ActiveRecord::Migration[8.1]
  def change
    create_table :follower_email_blocks do |t|
      t.references :organization, null: false, foreign_key: { on_delete: :cascade }
      t.integer :emails, null: false
      t.integer :price_cents, null: false
      t.references :bought_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :follower_email, foreign_key: { on_delete: :nullify }
      t.timestamps
    end
    add_column :follower_emails, :paid_emails_used, :integer, null: false, default: 0
  end
end
