# frozen_string_literal: true

# Adds a course offering's settlement to the organization's open "course" payout
# run. Unlike a performer run, the money is already in CocoScout's balance
# (students paid over the enrollment period), so a course run skips funding
# entirely — it just transfers held funds out:
#
#   * instructor payments  -> the instructor Person's Connect account
#   * the org's remainder   -> the Organization's own Connect account
#
# One PayoutBatchItem per payee (their total = one transfer), one
# PayoutContribution per source. Idempotent per source, so re-settling the same
# course restates amounts instead of double-adding. Only payees who can actually
# receive Stripe payouts are added; the rest stay owed (unpayable) until they
# connect a bank.
class CoursePayoutRunService
  Result = Struct.new(:batch, :added, :skipped, keyword_init: true)

  class << self
    def add_to_run!(payout, added_by: nil)
      offering = payout.course_offering
      organization = offering.production.organization
      added = 0
      skipped = 0
      batch = nil

      ActiveRecord::Base.transaction do
        batch = PayoutBatch.open_for(organization, kind: "course", created_by: added_by)
        label = "Course: #{offering.title}"

        # Instructor (and other Person) payments recorded on the payout.
        payout.line_items.includes(:payee).each do |line|
          next if line.paid?

          if upsert_contribution(batch, line.payee, line, line.amount_cents.to_i, label) == :added
            added += 1
          else
            skipped += 1
          end
        end

        # The organization keeps whatever's left after those payments.
        org_keeps_cents = payout.net_revenue_cents.to_i - payout.total_payout_cents.to_i
        if org_keeps_cents.positive?
          if upsert_contribution(batch, organization, payout, org_keeps_cents, "#{label} — organization's share") == :added
            added += 1
          else
            skipped += 1
          end
        end

        batch.recalculate_total!
      end

      Result.new(batch: batch, added: added, skipped: skipped)
    end

    private

    # Create or refresh the contribution for a given source. Returns :added when
    # it lands in the open run, :skipped when the payee can't be paid yet or the
    # contribution already belongs to a closed (paid) run.
    def upsert_contribution(batch, payee, source, cents, label)
      return :skipped unless payable?(payee) && cents.positive?

      existing = PayoutContribution.find_by(source: source)
      if existing
        return :skipped if existing.payout_batch_item&.paid? || !existing.payout_batch&.open?

        existing.update!(amount_cents: cents, label: label)
        resum_item(existing.payout_batch_item)
        return :added
      end

      item = batch.items.find_by(payee: payee) ||
        batch.items.create!(payee: payee, amount_cents: cents, status: "pending")
      PayoutContribution.create!(
        payout_batch: batch, payout_batch_item: item, payee: payee,
        source: source, amount_cents: cents, label: label, description: payee.try(:name)
      )
      resum_item(item)
      :added
    end

    # Course items are simply the sum of their contributions (no performer
    # net-settle against advances — that's a performer-run concern).
    def resum_item(item)
      item.update!(amount_cents: item.payout_contributions.sum(:amount_cents))
    end

    def payable?(payee)
      payee.present? && payee.respond_to?(:can_receive_payouts?) && payee.can_receive_payouts?
    end
  end
end
