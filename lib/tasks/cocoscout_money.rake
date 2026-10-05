# frozen_string_literal: true

namespace :finances do
  desc "Import every Stripe balance transaction since the account opened, and match each to its record"
  task import_stripe: :environment do
    count = StripeBalanceImport.run!(full: true)
    puts "Imported #{count} Stripe balance lines."
    StripeBalanceTransaction.group(:category, :match_status).count.sort.each do |(category, status), n|
      puts "  #{category.ljust(22)} #{status.ljust(10)} #{n}"
    end
  end

  desc "Bring in every bill Stripe sent every org"
  task sync_invoices: :environment do
    BillingInvoiceSync.sync_all!
    puts "#{BillingInvoice.count} bills: #{BillingInvoice.group(:kind, :status).count.map { |(k, s), n| "#{k}/#{s} #{n}" }.join(', ')}"
  end
end

namespace :cocoscout_ledger do
  desc "Post CocoScout's own ledger for history. Dry run by default; cocoscout_ledger:backfill[post] keeps it."
  task :backfill, [ :mode ] => :environment do |_t, args|
    dry_run = args[:mode] != "post"
    fmt = ->(cents) { cents.nil? ? "unavailable" : format("$%.2f", cents / 100.0) }
    puts dry_run ? "DRY RUN — posted inside a transaction, then rolled back." : "POSTING CocoScout's ledger."
    result = CocoScoutLedgerBackfill.run!(dry_run: dry_run)
    result.counts.each { |name, n| puts "  #{n} #{name}" }
    puts
    puts "CocoScout's ledger by kind:"
    result.by_type.sort.each { |type, cents| puts "  #{CocoScoutLedgerEntry.label(type).ljust(42)} #{fmt.call(cents)}" }
    c = result.check
    puts
    puts "Stripe balance:           #{fmt.call(c['stripe_balance_cents'])}"
    puts "Imported Stripe lines:    #{fmt.call(c['imported_net_cents'])}#{' (import incomplete)' unless c['details']['import_complete']}"
    puts "Held for theaters:        #{fmt.call(c['held_for_orgs_cents'])}"
    puts "CocoScout's own:          #{fmt.call(c['cocoscout_cents'])}"
    puts "Difference:               #{fmt.call(c['difference_cents'])}"
    puts "Unmatched Stripe lines:   #{c['unmatched_count']}, amounts that disagree: #{c['mismatch_count']}, ours missing from Stripe: #{c['details']['missing_count']}"
    puts
    puts dry_run ? "Nothing was kept." : "Posted. Review the Stripe check page, then record the opening difference there (or cocoscout_ledger:opening_difference[post])."
  end

  desc "Record today's check difference as CocoScout's opening difference. Dry run by default."
  task :opening_difference, [ :mode ] => :environment do |_t, args|
    row = PlatformReconciliationCheck.run!
    puts "Difference today: #{format('$%.2f', row.difference_cents.to_i / 100.0)}"
    if args[:mode] == "post"
      entry = CocoScoutLedgerBackfill.record_opening_difference!(row)
      puts entry ? "Recorded." : "Nothing recorded (no difference, or one was recorded already)."
      PlatformReconciliationCheck.run!
    else
      puts "Dry run: re-run as cocoscout_ledger:opening_difference[post] to record it."
    end
  end
end
