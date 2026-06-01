# frozen_string_literal: true

# Block 2 of the Mics Finder build. Producer/claim/challenge/suggestion
# tables + hub editor membership. Pure additive — no changes to existing
# CocoScout tables.
class CreateMicsProducerTables < ActiveRecord::Migration[8.1]
  def change
    # Pending field on Mic, so submissions enter a moderation state without
    # adding another status enum.
    add_column :mics, :pending, :boolean, null: false, default: false
    add_index :mics, :pending, where: "pending = true"

    create_table :mic_producers do |t|
      t.references :mic, null: false, foreign_key: true
      t.bigint :user_id, null: false
      # producer | co_producer | host
      t.integer :role, null: false, default: 0
      t.datetime :accepted_at
      t.timestamps
    end
    add_index :mic_producers, :user_id
    add_index :mic_producers, %i[mic_id user_id], unique: true

    create_table :mic_claims do |t|
      t.references :mic, null: false, foreign_key: true
      t.bigint :claimant_user_id, null: false
      # pending | approved | rejected
      t.integer :status, null: false, default: 0
      # producer | co_producer
      t.integer :role, null: false, default: 0
      t.jsonb :proof, null: false, default: {}
      t.bigint :adjudicator_user_id
      t.datetime :decided_at
      t.text :reason
      t.timestamps
    end
    add_index :mic_claims, :claimant_user_id
    add_index :mic_claims, :status

    create_table :mic_challenges do |t|
      t.references :mic, null: false, foreign_key: true
      t.bigint :challenger_user_id, null: false
      t.bigint :target_user_id
      t.text :reason
      t.jsonb :evidence, null: false, default: {}
      # pending | replaced | co_produce | dismissed | needs_info
      t.integer :status, null: false, default: 0
      t.bigint :adjudicator_user_id
      t.datetime :decided_at
      t.timestamps
    end
    add_index :mic_challenges, :challenger_user_id
    add_index :mic_challenges, :status

    create_table :mic_suggestions do |t|
      t.references :mic, null: false, foreign_key: true
      t.bigint :submitter_user_id
      t.string :submitter_email
      # pending | approved | rejected
      t.integer :status, null: false, default: 0
      t.jsonb :payload, null: false, default: {}
      t.text :note
      t.bigint :adjudicator_user_id
      t.datetime :decided_at
      t.timestamps
    end
    add_index :mic_suggestions, :status

    create_table :city_hub_memberships do |t|
      t.references :city_hub, null: false, foreign_key: true
      t.bigint :user_id, null: false
      # editor | viewer
      t.integer :role, null: false, default: 0
      t.timestamps
    end
    add_index :city_hub_memberships, %i[city_hub_id user_id], unique: true
    add_index :city_hub_memberships, :user_id
  end
end
