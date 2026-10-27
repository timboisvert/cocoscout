# frozen_string_literal: true

# The bank debit that was funding a payout run bounced. Nobody was told before —
# the run just sat there marked failed while everyone assumed money was moving,
# and the payees had already been told their money was on its way.
class PayoutFundingFailedNotificationJob < ApplicationJob
  include PayoutRunManagerNotice

  queue_as :default

  def perform(payout_batch_id)
    batch = PayoutBatch.find_by(id: payout_batch_id)
    return unless batch&.funding_status == "failed"

    notify_managers(batch, template_key: "payout_funding_failed", variables: {})
  end
end
