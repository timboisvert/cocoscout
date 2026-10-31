# frozen_string_literal: true

# Money recorded by hand (Books V1.3, plan C2): income that didn't come
# through CocoScout, spending outside it, and money moved between the
# organization's own accounts. Each posts one "recorded" entry.
class CreateMoneyRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :money_records do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :kind, null: false # in / out / move
      t.date :on, null: false
      t.integer :amount_cents, null: false
      t.string :category_key # a MoneyCategories key, or account_<id>
      t.string :counterparty
      t.references :production, foreign_key: true
      t.references :show, foreign_key: true
      t.string :via # in / out: bank, card, door_cash, owed
      t.string :from_account # move: bank, door_cash, credit_card
      t.string :to_account
      t.text :memo
      t.references :recorded_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :money_records, %i[organization_id on]
  end
end
