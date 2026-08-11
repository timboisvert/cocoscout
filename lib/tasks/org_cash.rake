# frozen_string_literal: true

namespace :org_cash do
  desc "Backfill the per-org cash ledger from history. Dry-run by default; pass [post] to write."
  task :backfill, [ :mode ] => :environment do |_t, args|
    dry_run = args[:mode] != "post"

    puts dry_run ? "DRY RUN — nothing will be written. Re-run as org_cash:backfill[post] to post." : "POSTING entries."
    puts

    result = OrgCashBackfill.run!(dry_run: dry_run)

    fmt = ->(cents) { format("$%.2f", cents / 100.0) }
    result.rows.each do |row|
      puts "#{row.organization.name} (##{row.organization.id})"
      puts "  course net:        +#{fmt.call(row.course_net_cents)}"
      puts "  refunds:           -#{fmt.call(row.refund_cents)}" if row.refund_cents.positive?
      puts "  contract payments: +#{fmt.call(row.contract_cents)}" if row.contract_cents.positive?
      puts "  course-run sent:   -#{fmt.call(row.course_run_debits_cents)}" if row.course_run_debits_cents.positive?
      puts "  offline payouts:   -#{fmt.call(row.offline_org_payout_cents)}" if row.offline_org_payout_cents.positive?
      puts "  funded residue:    +#{fmt.call(row.opening_balance_cents)}" if row.opening_balance_cents.positive?
      puts "  TOTAL:              #{fmt.call(row.total_cents)}"
      puts
    end

    puts "=" * 50
    puts "Sum of all org ledgers: #{fmt.call(result.total_cents)}"
    if result.stripe_balance_cents
      puts "Actual Stripe balance:  #{fmt.call(result.stripe_balance_cents)} (available + pending)"
      puts "Residual (CocoScout's share — fees, subscriptions): #{fmt.call(result.stripe_balance_cents - result.total_cents)}"
    else
      puts "Stripe balance: unavailable (no API key or API error)"
    end

    unless dry_run
      puts
      puts "Posted. Re-run org_cash:backfill for a dry-run sanity check (should show the same totals)."
    end
  end
end
