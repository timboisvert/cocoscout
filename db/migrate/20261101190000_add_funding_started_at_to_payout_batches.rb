# frozen_string_literal: true

# When a payout run's bank debit started, so the month's bank debits count
# by when they happened (two free a month, then a fee on the usage bill),
# not by when the run was drafted.
class AddFundingStartedAtToPayoutBatches < ActiveRecord::Migration[8.0]
  def change
    add_column :payout_batches, :funding_started_at, :datetime
  end
end
