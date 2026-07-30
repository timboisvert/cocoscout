# frozen_string_literal: true

namespace :contracts do
  desc "Backfill v2 settlement dimensions (settlement_basis + who_sells_tickets) onto existing contracts. DRY_RUN=1 to preview."
  task backfill_settlement: :environment do
    dry = ENV["DRY_RUN"] == "1"
    result = ContractSettlementBackfill.run(dry_run: dry)
    puts "#{dry ? '[dry run] ' : ''}migrated=#{result.migrated} skipped=#{result.skipped} mismatches=#{result.mismatches.size}"
    result.mismatches.each do |m|
      puts "  mismatch: contract ##{m[:contract_id]} derived=#{m[:derived]} existing=#{m[:existing].inspect} (left unchanged — review)"
    end
  end

  desc "Fix revenue-share payments generated backwards for we-sell deals (we hold the money → we pay them their share). Idempotent. DRY_RUN=1 to preview."
  task backfill_revenue_share_direction: :environment do
    dry = ENV["DRY_RUN"] == "1"
    result = RevenueShareDirectionBackfill.run(dry_run: dry)
    puts "#{dry ? '[dry run] ' : ''}contracts_fixed=#{result.contracts_fixed} " \
         "draft_rows=#{result.draft_rows_fixed} payment_rows=#{result.payment_rows_fixed}"
  end
end
