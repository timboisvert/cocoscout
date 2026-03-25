class CreateFeatureCreditsAndRedemptions < ActiveRecord::Migration[8.1]
  def change
    create_table :feature_credits do |t|
      t.string :code, null: false
      t.text :description
      t.string :recipient_name
      t.string :feature_type, null: false, default: "courses"
      t.string :scope_type, null: false, default: "course_offering"
      t.integer :max_uses, default: 1
      t.integer :uses_count, default: 0, null: false
      t.boolean :active, default: true, null: false
      t.datetime :expires_at
      t.bigint :created_by_user_id
      t.timestamps
    end

    add_index :feature_credits, :code, unique: true
    add_index :feature_credits, :feature_type
    add_index :feature_credits, :active

    create_table :feature_credit_redemptions do |t|
      t.references :feature_credit, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.string :redeemable_type, null: false
      t.bigint :redeemable_id, null: false
      t.timestamps
    end

    add_index :feature_credit_redemptions, [ :redeemable_type, :redeemable_id ], name: "idx_fcr_redeemable"

    add_reference :course_offerings, :feature_credit_redemption, foreign_key: true, null: true
  end
end
