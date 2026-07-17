# frozen_string_literal: true

# Durable, tamper-proof record that a performer was paid through a payout run in
# a given billing month — what makes them a billable active performer ($3/month),
# mirroring StaffActivation. We charge when we pay them, matching the month
# Stripe charges us the active-account fee. Idempotent per (org, person, month).
class CreatePerformerActivations < ActiveRecord::Migration[8.1]
  def change
    create_table :performer_activations do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.date :billing_month, null: false
      t.datetime :first_activated_at
      t.datetime :reported_at
      t.timestamps
    end

    add_index :performer_activations, %i[organization_id person_id billing_month],
              unique: true, name: "idx_performer_activations_unique"
  end
end
