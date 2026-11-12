# frozen_string_literal: true

namespace :books do
  desc "Post (or restate) every historical row on the books. Dry run by default; books:backfill[post] writes. ORG=id limits it."
  task :backfill, [ :mode ] => :environment do |_t, args|
    dry_run = args[:mode] != "post"
    ids = ENV["ORG"].presence&.split(",")&.map(&:to_i)

    puts dry_run ? "DRY RUN — each organization is posted inside a transaction, then rolled back. Re-run as books:backfill[post] to keep it." : "POSTING to the books, one organization at a time."
    puts

    result = BooksBackfill.run!(dry_run: dry_run, organization_ids: ids)
    fmt = ->(cents) { format("$%.2f", cents / 100.0) }
    result.rows.each do |row|
      puts "#{row.organization.name} (##{row.organization.id}): #{row.cash_rows} cash rows, #{row.owed_rows} payout rows, #{row.financials} shows' financials, #{row.expenses} production expenses, #{row.contract_payments} paid contract payments, #{row.bills} CocoScout bills"
      paid = row.hand_paid
      if paid.lines.positive? || paid.guests.positive? || paid.contract_lines.positive?
        puts "  paid by hand before the payout ledger: #{paid.lines} payout lines, #{fmt.call(paid.cents)}, to #{paid.people} people, now on the ledger and the books. Nobody's balance moved."
        puts "  left off: #{paid.guests} guests' lines, #{fmt.call(paid.guest_cents)} (a guest has no account to post to)" if paid.guests.positive?
        puts "  left off: #{paid.contract_lines} lines on contract shows, #{fmt.call(paid.contract_cents)} (the contract's own payments already carry that money)" if paid.contract_lines.positive?
      end
      puts "  trial balance: #{fmt.call(row.trial_balance_cents)}#{' (OUT OF BALANCE)' unless row.trial_balance_cents.zero?}"
      if row.mismatches.empty?
        puts "  checks: the books agree with the records behind them"
      else
        row.mismatches.each { |m| puts "  MISMATCH #{m.account}: books #{fmt.call(m.books_cents)}, records #{fmt.call(m.expected_cents)} (#{fmt.call(m.difference_cents)})" }
      end
      puts
    end
    result.failures.each { |failure| puts "FAILED #{failure.organization.name} (##{failure.organization.id}): #{failure.error}. Nothing of theirs was kept." }
    puts if result.failures.any?
    puts "#{result.rows.size} organizations. #{dry_run ? 'Nothing was kept.' : 'Posted.'}"
    abort "#{result.failures.size} failed. Fix what's named above and run it again with ORG=#{result.failures.map { |f| f.organization.id }.join(',')}." if result.failures.any?
  end
end
