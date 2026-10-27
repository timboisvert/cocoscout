# frozen_string_literal: true

# Two stamps that keep a payout run's manager notices to one each:
# funded_at (the "your run is funded" notice; Stripe repeats webhooks) and
# completion_notified_at (the "everyone's paid" / "partly paid" notice, once
# per completion; cleared when the run goes back to paying).
class AddNoticeStampsToPayoutBatches < ActiveRecord::Migration[8.1]
  def change
    add_column :payout_batches, :funded_at, :datetime
    add_column :payout_batches, :completion_notified_at, :datetime
  end
end
