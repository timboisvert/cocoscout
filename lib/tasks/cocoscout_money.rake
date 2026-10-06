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
    puts "On its way in:            #{fmt.call(c['details']['in_transit_cents'])}"
    (c["details"]["in_transit"] || []).each { |row| puts "    #{row['label']} (#{row['organization']}) #{fmt.call(row['cents'])}" }
    puts "Difference:               #{fmt.call(c['difference_cents'])}"
    puts "Unmatched Stripe lines:   #{c['unmatched_count']}, amounts that disagree: #{c['mismatch_count']}, ours missing from Stripe: #{c['details']['missing_count']}"
    StripeBalanceTransaction.needs_a_look.order(:occurred_at).each do |line|
      puts "    #{line.occurred_at.to_date} #{line.category} #{line.match_status} #{line.matched_type}##{line.matched_id} Stripe #{fmt.call(line.amount_cents)} ours #{fmt.call(line.expected_cents)}"
    end
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

namespace :usage do
  desc "Rebuild a month's billable staff and performers from paid work that's over (UsageRules). Dry run by default; usage:rebuild[2026-10,post] keeps it."
  task :rebuild, [ :month, :mode ] => :environment do |_t, args|
    month = Date.strptime(args[:month].to_s, "%Y-%m")
    post = args[:mode] == "post"
    puts post ? "REBUILDING #{month.strftime('%B %Y')}." : "DRY RUN for #{month.strftime('%B %Y')}: nothing is changed."
    changes = UsageRebuild.run!(month, post: post)
    puts "Every record already matches the paid work that's over." if changes.empty?
    changes.each do |change|
      puts "#{change.organization.name}, #{change.kind} (#{change.kept.size + change.added.size} counted after this):"
      puts "  stays (paid work that's over): #{change.kept.join(', ')}" if change.kept.any?
      puts "  remove (no paid work that month that's over): #{change.removed.join(', ')}" if change.removed.any?
      puts "  add (paid work that's over, not counted yet): #{change.added.join(', ')}" if change.added.any?
    end
    puts "Stripe already counted what was sent to it; the usage bill is corrected to these counts when Stripe drafts it." if changes.any? { |c| c.removed.any? }
  end
end

namespace :usage do
  desc "Usage bills charged more than the rule allows, and give it back. Dry run: usage:overbilled[ORG_ID]; then [ORG_ID,refund] or [ORG_ID,credit]."
  task :overbilled, [ :org_id, :how ] => :environment do |_t, args|
    organization = Organization.find(args[:org_id])
    how = args[:how]
    fmt = ->(cents) { format("$%.2f", cents / 100.0) }
    puts how ? "GIVING BACK the overcharges as a #{how}." : "DRY RUN for #{organization.name}: nothing is changed."
    rows = UsageOverbilling.rows(organization)
    BillingInvoice.where(organization: organization, kind: "usage").where.not(status: "paid").each do |open|
      puts "#{open.number}: #{open.status_label.downcase}; run again once it's paid."
    end
    rows.each do |row|
      puts "#{row.invoice.number} covers #{row.month.strftime('%B %Y')}: charged #{fmt.call(row.charged_cents)}" \
           "#{", already credited #{fmt.call(row.credited_cents)}" if row.credited_cents.positive?}; " \
           "owed #{fmt.call(row.owed_cents)} (#{row.staff} staff × $5, #{row.performers} performers × $3); overcharged #{fmt.call(row.over_cents)}"
      next unless how && row.over_cents.positive?

      note = UsageOverbilling.give_back!(row, how: how)
      puts "  credit note #{note.id} for #{fmt.call(row.over_cents)} (#{how})"
    end
    total = rows.sum(&:over_cents)
    puts "Overcharged in all: #{fmt.call(total)}."
  end
end
