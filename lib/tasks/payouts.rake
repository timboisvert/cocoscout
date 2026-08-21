# frozen_string_literal: true

namespace :payouts do
  desc "Fold open course-kind draft runs into each org's performer run (one payout rail)"
  task fold_course_drafts: :environment do
    drafts = PayoutBatch.of_kind("course").open_runs.includes(payout_contributions: :source)

    drafts.each do |batch|
      org = batch.organization

      # The course payouts whose lines rode this draft — re-added below through
      # the (now performer-run) service, which also posts their earnings.
      course_payouts = batch.payout_contributions.filter_map { |c|
        case c.source
        when CourseOfferingPayout then c.source
        when CourseOfferingPayoutLineItem then c.source.course_offering_payout
        end
      }.uniq

      puts "Run ##{batch.id} (#{org.name}): folding #{batch.payout_contributions.size} line(s) into the performer run"

      # Same cascade the discard flow uses: items, contributions (and any
      # ledger entries they posted — course drafts posted none) go with it.
      batch.destroy!

      course_payouts.each { |payout| CoursePayoutRunService.add_to_run!(payout) }
      remitted = ContractPaymentCollection.remit_pending!(org)
      puts "  re-added #{course_payouts.size} course payout(s), re-remitted #{remitted} contract payment(s)"
    end

    remaining = PayoutBatch.of_kind("course").open_runs.count
    puts "Done. #{remaining} open course draft(s) remain."
  end
end
