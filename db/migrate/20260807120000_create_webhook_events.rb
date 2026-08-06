# frozen_string_literal: true

# Webhook de-duplication. Stripe redelivers any event we don't answer 2xx, and
# our handlers move money — reversing a ledger entry twice, or re-running a
# funding advance, is not something to leave to luck.
#
# (An earlier create_webhook_logs migration exists but never made it into the
# schema and nothing ever used it; this is the real one.)
class CreateWebhookEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_events do |t|
      t.string :provider, null: false, default: "stripe"
      t.string :event_id, null: false
      t.string :event_type
      t.datetime :created_at, null: false
    end

    # The claim: whoever inserts first handles the event.
    add_index :webhook_events, [ :provider, :event_id ], unique: true
    add_index :webhook_events, :created_at
  end
end
