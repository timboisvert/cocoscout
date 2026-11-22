# frozen_string_literal: true

# Every morning, after the night's ticket money is released (4am), each payout
# run that's paying from the CocoScout balance ("awaiting_balance") pays
# whoever the balance now covers, in pay order, and funds the rest once the
# balance covers everyone left or its scheduled bank debit has come
# (PayoutBatchService.advance_from_balance!). Managers get a notification when
# a morning pays more.
class PayoutBalanceWavesJob < ApplicationJob
  queue_as :default

  def perform
    PayoutBatch.where(status: "funding", funding_status: "awaiting_balance").find_each do |batch|
      PayoutBatchService.advance_from_balance!(batch, notify: true)
    rescue PayoutBatchService::Error => e
      # The reason is on the run (funding_error); a manager tries the bank again.
      Rails.logger.info("[PayoutBalanceWavesJob] run #{batch.id}: #{e.message}")
    rescue StandardError => e
      # One run's trouble never holds up another's people.
      Rails.logger.error("[PayoutBalanceWavesJob] run #{batch.id}: #{e.class} #{e.message}")
      Sentry.capture_exception(e) if defined?(Sentry)
    end
  end
end
