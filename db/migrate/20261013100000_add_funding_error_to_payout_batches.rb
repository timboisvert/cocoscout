# frozen_string_literal: true

# Why a payout run failed to fund, in Stripe's own words. Run 29 (2026-10-13)
# failed and the only record of the reason was a flash message that was gone
# by the time anyone looked; diagnosing it took a prod console. Cleared at the
# start of each new funding attempt.
class AddFundingErrorToPayoutBatches < ActiveRecord::Migration[8.1]
  def change
    add_column :payout_batches, :funding_error, :string
  end
end
