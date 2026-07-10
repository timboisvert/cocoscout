# frozen_string_literal: true

namespace :payout_ledger do
  desc "Backfill the payout ledger from existing calculated show payouts. " \
       "Dry-run by default; pass EXECUTE=1 to apply."
  task backfill: :environment do
    execute = ENV["EXECUTE"] == "1"
    puts(execute ? "Running (EXECUTE=1) — posting ledger entries." : "DRY RUN — pass EXECUTE=1 to apply.\n")

    scope = ShowPayout.where.not(calculated_at: nil)
    total_payouts = scope.count
    line_item_count = 0

    scope.find_each do |payout|
      eligible = payout.line_items.reject(&:is_guest?).select { |li| li.payee_id.present? }
      line_item_count += eligible.size
      payout.sync_earnings_to_ledger! if execute
    end

    puts "#{execute ? 'Posted' : 'Would post'} entries for #{line_item_count} line item(s) " \
         "across #{total_payouts} calculated show payout(s)."

    # Reconciliation: ledger balance per org should match the sum of unpaid net
    # payouts (earnings minus recorded payouts) once backfilled.
    puts "\nReconciliation (org → ledger balance):"
    Organization.find_each do |org|
      next if org.payout_ledger_entries.none?

      ledger_total = org.payout_ledger_entries.sum(:amount_cents)
      puts "  #{org.name} (##{org.id}) → #{format('$%.2f', ledger_total / 100.0)} owed across all payees"
    end
  end
end
