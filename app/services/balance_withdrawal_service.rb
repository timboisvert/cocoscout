# frozen_string_literal: true

# Sends money from the theater's CocoScout balance to its own bank: one
# Stripe transfer to the theater's connected account, which Stripe pays out
# to the bank on its usual schedule. Only spendable money (CocoScoutBalance)
# can go, so nothing held for an upcoming show — or for a payout run — ever
# leaves early.
class BalanceWithdrawalService
  class Error < StandardError; end

  # What the theater's open payout run will need from the balance to go out
  # without a bank debit (what's left after held money and funding credit).
  def self.open_run_need_cents(organization)
    run = PayoutBatch.current_open_draft(organization)
    return 0 unless run&.total_cents.to_i.positive?

    fundable = [ run.total_cents - run.held_cents, 0 ].max
    [ fundable - PayoutFundingCredit.available_cents(organization), 0 ].max
  end

  def self.withdraw!(organization, amount_cents:, by: nil, automatic: false)
    raise Error, "Connect your organization's bank first: it's where withdrawals go." unless organization.can_receive_payouts?

    amount_cents = amount_cents.to_i
    withdrawal = nil
    OrgCashEntry.with_org_lock(organization) do
      available = CocoScoutBalance.available_cents(organization)
      raise Error, "Enter an amount to withdraw." unless amount_cents.positive?
      if amount_cents > available
        raise Error, "Only #{ActiveSupport::NumberHelper.number_to_currency(available / 100.0)} is available to withdraw."
      end

      withdrawal = organization.balance_withdrawals.create!(amount_cents: amount_cents, requested_by: by, automatic: automatic)
      OrgCashEntry.post!(organization: organization, entry_type: "transfer", amount_cents: -amount_cents,
                         source: withdrawal, description: "Withdrawal to your bank")
    end

    transfer = Stripe::Transfer.create(
      { amount: amount_cents, currency: "usd", destination: organization.stripe_account_id,
        transfer_group: "org_#{organization.id}",
        metadata: { balance_withdrawal_id: withdrawal.id, organization_id: organization.id } },
      { idempotency_key: "balance-withdrawal-#{withdrawal.id}" }
    )
    withdrawal.update!(status: "sent", stripe_transfer_id: transfer.id)
    # The money has moved. Nothing after this may make the manager think it
    # didn't: the books entry and the notice are logged if they fail.
    begin
      LedgerPosting.post!(organization: organization, source: withdrawal, kind: "withdrawal",
                          entry_date: Date.current, cash_date: Date.current, memo: "Withdrawal to your bank",
                          lines: [
                            { account: :bank, amount_cents: amount_cents },
                            { account: :cocoscout_balance, amount_cents: -amount_cents }
                          ])
      TicketingNotifier.notify(organization, :withdrawal, variables: TicketingNotificationContent.withdrawal(withdrawal))
    rescue StandardError => e
      raise if Rails.env.test?

      Rails.logger.error("[BalanceWithdrawalService] withdrawal #{withdrawal.id} sent, follow-up failed: #{e.class}: #{e.message}")
    end
    withdrawal
  rescue Stripe::StripeError => e
    # Nothing left: the money stays in the balance.
    if withdrawal
      OrgCashEntry.unpost!(source: withdrawal, entry_type: "transfer")
      withdrawal.update!(status: "failed", error: e.message)
      TicketingNotifier.notify(organization, :withdrawal, variables: TicketingNotificationContent.withdrawal(withdrawal))
    end
    raise Error, "Stripe couldn't send it: #{e.message}"
  end

  # Stripe's payout from the theater's account reached their bank.
  def self.landed!(withdrawal, payout_id:)
    return withdrawal unless withdrawal.status.in?(%w[sent bank_rejected])

    withdrawal.update!(status: "paid", stripe_payout_id: payout_id, paid_at: Time.current, error: nil)
    withdrawal
  end

  # Their bank turned the payout down. The money is in the theater's own
  # Stripe account, not ours: Stripe pays it again once they fix the bank.
  def self.bank_rejected!(withdrawal, payout_id:, reason:)
    return withdrawal unless withdrawal.status.in?(%w[sent paid])

    withdrawal.update!(status: "bank_rejected", stripe_payout_id: payout_id, error: reason)
    withdrawal
  end

  # The transfer was taken back: the money is in our balance again, so the
  # theater's balance and books get it back.
  def self.reversed!(withdrawal)
    return withdrawal if withdrawal.status.in?(BalanceWithdrawal::RETURNED)

    withdrawal.transaction do
      OrgCashEntry.unpost!(source: withdrawal, entry_type: "transfer")
      LedgerPosting.unpost!(source: withdrawal, kind: "withdrawal")
      withdrawal.update!(status: "reversed")
    end
    withdrawal
  end
end
