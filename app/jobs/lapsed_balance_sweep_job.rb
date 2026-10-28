# frozen_string_literal: true

# Daily, for every organization whose money pools but that isn't Pro anymore
# (Tim, 2026-10-25): the balance page is Pro, so it can't withdraw by hand.
# Its spendable balance goes to its bank instead, less what its open payout
# run (course instructors still ride it) needs to go out without a bank
# debit. With no bank connected yet, the money waits; Course settings, which
# isn't Pro, is where it connects one.
class LapsedBalanceSweepJob < ApplicationJob
  queue_as :default

  def perform
    Organization.where.not(balance_pooled_at: nil).find_each do |organization|
      next if organization.feature_available?(:ticketing)
      next unless organization.can_receive_payouts?

      cents = CocoScoutBalance.available_cents(organization) - BalanceWithdrawalService.open_run_need_cents(organization)
      next if cents < BalanceAutoWithdrawJob::MINIMUM_CENTS

      BalanceWithdrawalService.withdraw!(organization, amount_cents: cents, automatic: true)
    rescue StandardError => e
      Rails.logger.error("[LapsedBalanceSweepJob] org #{organization.id}: #{e.class}: #{e.message}")
    end
  end
end
