# frozen_string_literal: true

# Stamped when we've told this payee their money is on its way, so a payee is
# never notified twice for the same run. Both submission paths are re-runnable
# — PayoutBatchService.pay_remaining! re-enters process!, and
# CoursePayoutRunExecutor.pay! is deliberately idempotent — so without this a
# retry would send a duplicate "money's coming" every time.
class AddPayeeNotifiedAtToPayoutBatchItems < ActiveRecord::Migration[8.1]
  def change
    add_column :payout_batch_items, :payee_notified_at, :datetime
  end
end
