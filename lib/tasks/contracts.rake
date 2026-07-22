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
end
