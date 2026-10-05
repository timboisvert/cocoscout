# frozen_string_literal: true

# Copies CocoScout's Stripe balance transactions (the platform account's
# statement) into StripeBalanceTransaction and matches each one. The first
# run takes everything since the account opened; after that it re-reads the
# last week, which also refreshes bank debits still pending.
class StripeBalanceImport
  OVERLAP = 7.days

  def self.run!(full: false)
    last = StripeBalanceTransaction.maximum(:occurred_at)
    params = { limit: 100, expand: [ "data.source" ] }
    params[:created] = { gte: (last - OVERLAP).to_i } if last && !full
    count = 0
    Stripe::BalanceTransaction.list(params).auto_paging_each do |transaction|
      StripeBalanceTransaction.import!(transaction)
      count += 1
    end
    # Lines that arrived before their record (a bill synced later) match now.
    StripeTransactionMatcher.rematch_pending!
    count
  end
end
