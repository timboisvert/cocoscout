# frozen_string_literal: true

# A single line of detail inside a payout run: what a specific payee is being
# paid for. Many contributions roll up into one PayoutBatchItem (the payee's
# total / one Stripe transfer), which rolls up into a PayoutBatch (the run).
#
# For performer runs the `source` is a ShowPayoutLineItem (so a person paid for
# four shows has one item with four contributions). The unique source index
# keeps the same show payout from being added to a run twice.
class CreatePayoutContributions < ActiveRecord::Migration[8.1]
  def change
    create_table :payout_contributions do |t|
      t.references :payout_batch, null: false, foreign_key: true
      t.references :payout_batch_item, null: false, foreign_key: true
      t.references :payee, polymorphic: true, null: false
      t.references :source, polymorphic: true, null: true
      t.bigint :amount_cents, null: false, default: 0
      t.string :label, null: false
      t.string :description

      t.timestamps
    end

    add_index :payout_contributions, %i[source_type source_id], unique: true,
              where: "source_id IS NOT NULL", name: "index_payout_contributions_on_source_unique"
  end
end
