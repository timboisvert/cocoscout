# frozen_string_literal: true

# Sends money from the theater's CocoScout balance to its own bank: one
# Stripe transfer to the theater's connected account, which Stripe pays out
# to the bank on its usual schedule. Only spendable money (TicketBalance)
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
      available = TicketBalance.available_cents(organization)
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
    LedgerPosting.post!(organization: organization, source: withdrawal, kind: "withdrawal",
                        entry_date: Date.current, cash_date: Date.current, memo: "Withdrawal to your bank",
                        lines: [
                          { account: :bank, amount_cents: amount_cents },
                          { account: :cocoscout_balance, amount_cents: -amount_cents }
                        ])
    withdrawal
  rescue Stripe::StripeError => e
    # Nothing left: the money stays in the balance.
    if withdrawal
      OrgCashEntry.unpost!(source: withdrawal, entry_type: "transfer")
      withdrawal.update!(status: "failed", error: e.message)
    end
    raise Error, "Stripe couldn't send it: #{e.message}"
  end
end
