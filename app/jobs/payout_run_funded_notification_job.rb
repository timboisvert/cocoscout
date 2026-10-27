# frozen_string_literal: true

# The bank debit funding a payout run settled (the webhook path): tell the
# organization's chosen people the run is funded and payments are going out.
# Enqueued once, from PayoutBatchService.advance_funding!, guarded by
# funded_at (Stripe repeats webhooks). A run funded in the same request as
# its submission says so in the submitted notice instead.
class PayoutRunFundedNotificationJob < ApplicationJob
  include PayoutRunManagerNotice

  queue_as :default

  def perform(payout_batch_id)
    batch = PayoutBatch.find_by(id: payout_batch_id)
    return unless batch&.funded_at.present?

    notify_managers(batch, template_key: "payout_run_funded", variables: {})
  end
end
