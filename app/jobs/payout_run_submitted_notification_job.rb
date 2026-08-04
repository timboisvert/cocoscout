# frozen_string_literal: true

# Emails the org's chosen managers that a payout run was submitted (funded).
# Enqueued from PayoutBatchService.fund! so the request thread never waits on
# mail. Recipients come from Money settings → Notifications; none chosen means
# nothing sends.
class PayoutRunSubmittedNotificationJob < ApplicationJob
  queue_as :default

  def perform(payout_batch_id)
    batch = PayoutBatch.find_by(id: payout_batch_id)
    return unless batch
    # Only runs that actually started funding — a failed fund! never notifies.
    return unless batch.in_flight? || batch.completed?

    batch.organization.payout_notification_users.find_each do |user|
      PayoutBatchMailer.submitted(batch: batch, user: user).deliver_now
    end
  end
end
