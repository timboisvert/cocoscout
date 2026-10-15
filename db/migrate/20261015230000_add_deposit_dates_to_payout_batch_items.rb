# frozen_string_literal: true

# A payee's pay has four stages (Tim, 2026-10-15): waiting for approval,
# approved, on its way, deposited. "Paid" on a run item only means we sent the
# transfer; the payout provider moves it on to their bank a couple of business
# days later. These record that last leg from the provider's payout events
# (ConnectPayoutTracker): when it's due to arrive, and when it was deposited.
class AddDepositDatesToPayoutBatchItems < ActiveRecord::Migration[8.1]
  def change
    add_column :payout_batch_items, :expected_deposit_on, :date
    add_column :payout_batch_items, :deposited_at, :datetime
  end
end
