# frozen_string_literal: true

# Daily, for every theater selling tickets:
#   1. The 12-month rule: money that has sat in the CocoScout balance for more
#      than a year goes back to the theater's bank, whatever its settings
#      (CocoScout holds money to pay its people, not to keep it). With no bank
#      connected yet, the theater is reminded once a month instead.
#   2. Automatic withdrawal, for theaters that turned it on: the spendable
#      balance goes to the bank on Mondays ("weekly"), or every day there's
#      something to send — the day after each show once its money settles
#      ("after_shows"). Off by default: money left here pays payout runs the
#      same day, without a bank debit.
class BalanceAutoWithdrawJob < ApplicationJob
  queue_as :default

  # Not worth a transfer below this.
  MINIMUM_CENTS = 100

  def perform(today = Date.current)
    TicketingProfile.where(enabled: true).includes(:organization).find_each do |profile|
      organization = profile.organization
      send_back_aged_money(organization, today)
      next if profile.auto_withdraw == "off"
      next if profile.auto_withdraw == "weekly" && !today.monday?
      next unless organization.can_receive_payouts?
      # A payout run is paying its people from this balance as it clears.
      next if organization.payout_batches.where(status: "funding", funding_status: "awaiting_balance").exists?

      cents = CocoScoutBalance.available_cents(organization)
      next if cents < MINIMUM_CENTS

      BalanceWithdrawalService.withdraw!(organization, amount_cents: cents, automatic: true)
    rescue StandardError => e
      Rails.logger.error("[BalanceAutoWithdrawJob] org #{profile.organization_id}: #{e.class}: #{e.message}")
    end
  end

  private

  # Year-old money a payout run is waiting on stays: the run pays its people
  # with it the next morning (PayoutBalanceWavesJob), which beats sending it
  # to the bank only to debit the bank for the same people.
  def send_back_aged_money(organization, today)
    aged = CocoScoutBalance.aged_cents(organization) - BalanceWithdrawalService.waiting_run_need_cents(organization)
    return if aged < MINIMUM_CENTS

    if organization.can_receive_payouts?
      BalanceWithdrawalService.withdraw!(organization, amount_cents: aged, automatic: true)
    else
      TicketingNotifier.notify(organization, :withdrawal, variables: TicketingNotificationContent.held_a_year(aged),
                                                          occasion: today.strftime("%Y-%m"), once: true)
    end
  end
end
