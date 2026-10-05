# frozen_string_literal: true

# Follows money we sent to a connected account on to its bank. Stripe pays a
# connected account out in batches, so a payout can carry several of our
# transfers; it never says which by amount alone. The payout's own balance
# transactions do: each is the destination payment of one transfer, and that
# payment names the transfer it came from.
#
#   payout.paid   — a theater's withdrawals in it reached the bank
#   payout.failed — the bank turned it down: a theater's withdrawals wait in
#                   its Stripe account; a payee's run payments go back to the
#                   run (PayoutBatchService.return_item!)
class ConnectPayoutTracker
  # The ids of our transfers a connected account's payout carried. Nil when
  # Stripe can't be asked, so callers can fall back.
  def self.transfer_ids(payout_id, account_id)
    transactions = Stripe::BalanceTransaction.list(
      { payout: payout_id, type: "payment", expand: [ "data.source" ], limit: 100 },
      { stripe_account: account_id }
    )
    transactions.auto_paging_each.filter_map do |transaction|
      source = transaction.source
      transfer = source.respond_to?(:source_transfer) ? source.source_transfer : nil
      transfer.is_a?(String) ? transfer : transfer&.id
    end
  rescue Stripe::StripeError => e
    Rails.logger.warn("[ConnectPayoutTracker] couldn't list payout #{payout_id} on #{account_id}: #{e.message}")
    nil
  end

  def self.paid!(payout, account_id)
    ids = transfer_ids(payout.id, account_id)
    return if ids.blank?

    BalanceWithdrawal.where(stripe_transfer_id: ids).find_each do |withdrawal|
      BalanceWithdrawalService.landed!(withdrawal, payout_id: payout.id)
    end
  end

  # Returns the matched run items when the transfers could be read, or nil
  # when Stripe couldn't be asked (the caller then falls back to amounts).
  def self.failed!(payout, account_id, reason:)
    ids = transfer_ids(payout.id, account_id)
    return nil if ids.nil?

    BalanceWithdrawal.where(stripe_transfer_id: ids).find_each do |withdrawal|
      BalanceWithdrawalService.bank_rejected!(withdrawal, payout_id: payout.id, reason: reason)
    end
    PayoutBatchItem.where(stripe_transfer_id: ids, status: "paid").to_a
  end
end
