# frozen_string_literal: true

# Season subscriptions (advanced ticketing plan §2a, V1.4 step 7): a pass of
# kind "subscription" keeps each buyer in the same seats on every date; the
# subscriber's standing record; renewal by invitation with the seats held.
class CreateTicketSubscriptions < ActiveRecord::Migration[8.1]
  def change
    add_reference :ticket_passes, :renews_from, foreign_key: { to_table: :ticket_passes }
    add_column :ticket_passes, :renewal_closes_at, :datetime

    create_table :ticket_subscriptions do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :ticket_pass, null: false, foreign_key: true
      t.references :ticket_purchase, foreign_key: true
      t.references :follower, foreign_key: true
      t.references :renewed_from, foreign_key: { to_table: :ticket_subscriptions }
      t.references :renewal_pass, foreign_key: { to_table: :ticket_passes }
      t.string :token, null: false
      t.string :status, null: false, default: "pending"
      t.string :buyer_name
      t.string :buyer_email
      t.jsonb :seat_ids, null: false, default: []
      t.integer :quantity, null: false, default: 1
      t.integer :renewal_reminders, null: false, default: 0
      t.timestamps
      t.index :token, unique: true
    end

    add_reference :ticket_seat_holds, :ticket_subscription, foreign_key: true

    reversible do |dir|
      dir.up { TicketingTemplates.ensure!(keys: %w[ticket_subscription_welcome ticket_subscription_renewal]) }
    end
  end
end
