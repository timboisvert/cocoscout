# frozen_string_literal: true

# Adds a course offering's settlement to the organization's open PERFORMER
# payout run — there is one payout rail: performers, contractors, course
# instructors, and the org's own remittances all ride the same run (staff pay
# is the only separate run). The course money is already in CocoScout's balance
# (students paid over the enrollment period), so these lines are "held funds"
# (PayoutContribution#held_funds?) — funding the run never debits the org's
# bank for them:
#
#   * instructor payments  -> the instructor Person's Connect account
#   * the org's remainder  -> the Organization's own Connect account
#
# One PayoutBatchItem per payee (their total = one transfer), one
# PayoutContribution per source. Instructor/contractor lines post a real
# performer-ledger earning (source: the contribution, so removing the line
# reverses it) — the run then nets them against advances exactly like show pay.
# The org's remainder row stays off the ledger (the org has none); its item is
# just the sum of its lines. Idempotent per source, so re-settling the same
# course restates amounts instead of double-adding. The org's remainder only
# joins once the org's Stripe account can actually receive the transfer.
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
        batch = PayoutBatch.open_for(organization, kind: "performer", created_by: added_by)

        # CoursePayoutSettlement decides the final amounts (incl. the contract
        # rule that instructor pay comes out of the contractor's share), so the
        # run always matches what the payout page shows.
        CoursePayoutSettlement.new(payout).rows.each do |row|
          label = row[:is_org] ? "Course: #{offering.title} — organization's share" : "Course: #{offering.title}"
          if upsert_contribution(batch, row[:payee], row[:source], row[:amount_cents], label) == :added
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
        post_earning!(existing)
        existing.payout_batch_item&.settle_performer_amount!
        return :added
      end

      item = batch.items.find_by(payee: payee) ||
        batch.items.create!(payee: payee, amount_cents: cents, status: "pending")
      contribution = PayoutContribution.create!(
        payout_batch: batch, payout_batch_item: item, payee: payee,
        source: source, amount_cents: cents, label: label, description: payee.try(:name)
      )
      post_earning!(contribution)
      item.settle_performer_amount!
      :added
    end

    # A performer-run item pays the payee's net ledger balance, so a course line
    # must exist on the ledger as an earning or the run would settle it to zero.
    # Posted with the contribution as source: post! restates on recalculation,
    # and the contribution's dependent: :destroy reverses it when the line is
    # removed from the run. The org's remainder row posts nothing — the org has
    # no ledger; its item is summed from its lines instead.
    def post_earning!(contribution)
      return if contribution.payee_type == "Organization"

      PayoutLedgerEntry.post!(
        organization: contribution.payout_batch.organization,
        payee: contribution.payee,
        entry_type: "earning",
        amount_cents: contribution.amount_cents,
        source: contribution,
        description: contribution.label,
        category: "performer"
      )
    end

    # People (instructors/contractors) go on the run whether or not they've
    # connected a bank — same model as staffing/performers: their item stays
    # pending, the run drops back to draft after paying everyone else, and
    # re-running it pays them once they connect. The org's own remainder row is
    # different: it only joins once the org's Stripe account can actually
    # receive the transfer.
    def payable?(payee)
      return false if payee.blank?
      return true if PayoutBatchService::PAYABLE_TYPES.include?(payee.class.polymorphic_name)

      payee.respond_to?(:can_receive_payouts?) && payee.can_receive_payouts?
    end
  end
end
