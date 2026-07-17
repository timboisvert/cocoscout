# frozen_string_literal: true

# The per-payment staff fee was removed before launch (staffing is billed purely
# per active staff member; pay runs are unlimited). These columns are unused.
class DropExtraPaymentFeeFromPayoutBatches < ActiveRecord::Migration[8.1]
  def change
    remove_column :payout_batches, :extra_payment_fee_cents, :integer, default: 0, null: false
    remove_column :payout_batches, :fee_metered_at, :datetime
  end
end
