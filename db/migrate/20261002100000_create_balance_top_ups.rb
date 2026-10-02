# frozen_string_literal: true

# Money a theater adds to its CocoScout balance from its bank — most often
# to cover a refund after the show, once the show's money was spent. A
# refund waiting on it is kept here and issued the moment the money lands.
class CreateBalanceTopUps < ActiveRecord::Migration[8.1]
  def change
    create_table :balance_top_ups do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :requested_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.integer :amount_cents, null: false
      t.string :status, null: false, default: "pending"
      t.string :stripe_payment_intent_id
      t.jsonb :refund_request
      t.string :error
      t.timestamps
    end
    add_index :balance_top_ups, :stripe_payment_intent_id, unique: true, where: "stripe_payment_intent_id IS NOT NULL"
  end
end
