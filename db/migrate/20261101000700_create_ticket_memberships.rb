# frozen_string_literal: true

# Memberships (advanced ticketing plan §2b, V1.4 step 6): levels an
# organization defines from a menu of perks, the memberships people buy,
# the emailed codes that prove a buyer's email (the key to a buyer hub
# later), and a date's members-first on-sale time.
class CreateTicketMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :ticket_membership_levels do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.integer :price_cents, null: false, default: 0
      t.integer :period_months, null: false, default: 12
      t.string :status, null: false, default: "draft"
      t.integer :position, null: false, default: 0
      # The menu of perks, each on or off.
      t.integer :discount_percent, null: false, default: 0
      t.integer :presale_days, null: false, default: 0
      t.boolean :free_exchanges, null: false, default: false
      t.boolean :better_seats, null: false, default: false
      t.boolean :section_upgrade, null: false, default: false
      t.text :extras
      t.timestamps
    end

    create_table :ticket_memberships do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :ticket_membership_level, null: false, foreign_key: true
      t.references :ticket_purchase, foreign_key: true
      t.references :follower, foreign_key: true
      t.references :renewed_from, foreign_key: { to_table: :ticket_memberships }
      t.string :token, null: false
      t.string :status, null: false, default: "pending"
      t.string :holder_name
      t.string :holder_email
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.integer :price_cents, null: false, default: 0
      t.integer :tax_cents, null: false, default: 0
      t.integer :platform_fee_cents, null: false, default: 0
      t.integer :processing_cents, null: false, default: 0
      t.integer :buyer_fee_cents, null: false, default: 0
      t.integer :total_cents, null: false, default: 0
      t.integer :org_net_cents, null: false, default: 0
      t.integer :stripe_fee_cents
      t.datetime :paid_at
      t.integer :renewal_reminders, null: false, default: 0
      t.timestamps
      t.index :token, unique: true
      t.index %i[organization_id holder_email]
    end

    create_table :ticket_buyer_verifications do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :email, null: false
      t.string :code_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.integer :attempts, null: false, default: 0
      t.timestamps
      t.index %i[organization_id email]
    end

    add_reference :ticket_orders, :ticket_membership, foreign_key: true
    add_column :ticket_listings, :members_on_sale_at, :datetime

    reversible do |dir|
      dir.up { TicketingTemplates.ensure!(keys: %w[ticket_membership_welcome ticket_member_code ticket_membership_renewal]) }
    end
  end
end
