# frozen_string_literal: true

namespace :books do
  desc "Post every historical row to the books (Books stage B). Dry run by default; books:backfill[post] writes. ORG=id limits it."
  task :backfill, [ :mode ] => :environment do |_t, args|
    dry_run = args[:mode] != "post"
    ids = ENV["ORG"].presence&.split(",")&.map(&:to_i)

    puts dry_run ? "DRY RUN — posted inside a transaction, then rolled back. Re-run as books:backfill[post] to keep it." : "POSTING to the books."
    puts

    result = BooksBackfill.run!(dry_run: dry_run, organization_ids: ids)
    fmt = ->(cents) { format("$%.2f", cents / 100.0) }
    result.rows.each do |row|
      puts "#{row.organization.name} (##{row.organization.id}): #{row.cash_rows} cash rows, #{row.owed_rows} payout rows, #{row.financials} shows' financials, #{row.expenses} production expenses"
      puts "  trial balance: #{fmt.call(row.trial_balance_cents)}#{' (OUT OF BALANCE)' unless row.trial_balance_cents.zero?}"
      if row.mismatches.empty?
        puts "  checks: the books agree with the records behind them"
      else
        row.mismatches.each { |m| puts "  MISMATCH #{m.account}: books #{fmt.call(m.books_cents)}, records #{fmt.call(m.expected_cents)} (#{fmt.call(m.difference_cents)})" }
      end
      puts
    end
    puts "#{result.rows.size} organizations. #{dry_run ? 'Nothing was kept.' : 'Posted.'}"
  end
end
