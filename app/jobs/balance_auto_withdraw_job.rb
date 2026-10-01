# frozen_string_literal: true

# Daily: theaters that turned on automatic withdrawal get their spendable
# balance sent to their bank — on Mondays ("weekly"), or every day there's
# something to send, which is the day after each show once its money settles
# ("after_shows"). Off by default: money left here pays payout runs the same
# day, without a bank debit.
class BalanceAutoWithdrawJob < ApplicationJob
  queue_as :default

  # Not worth a transfer below this.
  MINIMUM_CENTS = 100

  def perform(today = Date.current)
    TicketingProfile.where(enabled: true).where.not(auto_withdraw: "off").includes(:organization).find_each do |profile|
      next if profile.auto_withdraw == "weekly" && !today.monday?

      organization = profile.organization
      next unless organization.can_receive_payouts?

      cents = TicketBalance.available_cents(organization)
      next if cents < MINIMUM_CENTS

      BalanceWithdrawalService.withdraw!(organization, amount_cents: cents, automatic: true)
    rescue StandardError => e
      Rails.logger.error("[BalanceAutoWithdrawJob] org #{profile.organization_id}: #{e.class}: #{e.message}")
    end
  end
end
