# frozen_string_literal: true

# The bank debit that was funding a payout run bounced. Nobody was told before —
# the run just sat there marked failed while everyone assumed money was moving,
# and the payees had already been told their money was on its way.
class PayoutFundingFailedNotificationJob < ApplicationJob
  include PayoutRunManagerNotice

  queue_as :default

  def perform(payout_batch_id)
    batch = PayoutBatch.find_by(id: payout_batch_id)
    return unless batch

    if batch.funding_status == "failed"
      notify_managers(batch, template_key: "payout_funding_failed", variables: {})
    elsif batch.funding_status == "awaiting_balance" && batch.funding_error.present?
      # The rest of a run that paid from the balance first: the people the
      # balance paid stay paid, so "nothing has been sent" would be untrue.
      waiting = batch.items.where(status: PayoutBatch::RETRYABLE_ITEM_STATUSES)
      paid = batch.items.where(paid_from_balance: true).count
      notify_managers(batch, template_key: "payout_rest_funding_failed", variables: {
        paid_count: "#{paid} #{paid == 1 ? 'payee' : 'payees'}",
        waiting_count: waiting.count,
        waiting_total: money(waiting.sum(:amount_cents))
      })
    end
  end
end
