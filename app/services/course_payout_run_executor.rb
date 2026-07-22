# frozen_string_literal: true

# Pays out a course payout run. The money is already in CocoScout's platform
# balance (students paid over the enrollment period), so there's no funding step:
# each item is a direct Stripe transfer from the platform balance to the payee's
# Connect account — instructors to their bank, the organization to its own.
#
# Each transfer is stamped with the course/payout it came from (traceable in the
# Stripe dashboard), and the organization's own share is recorded as an OrgPayout
# so the books show CocoScout remitted it. Idempotent: only pending items are
# transferred, so re-running never double-pays.
class CoursePayoutRunExecutor
  Result = Struct.new(:batch, :paid, :failed, keyword_init: true)

  class << self
    def pay!(batch)
      raise ArgumentError, "#{batch.kind} is not a course run" unless batch.kind == "course"

      paid = 0
      failed = 0
      batch.update!(status: "processing")

      batch.items.pending.includes(:payee, :payout_contributions).find_each do |item|
        transfer = Stripe::Transfer.create(
          amount: item.amount_cents,
          currency: "usd",
          destination: item.payee.stripe_account_id,
          metadata: transfer_metadata(item)
        )
        item.mark_paid!(transfer_id: transfer.id)
        record_org_payout!(item)
        paid += 1
      rescue Stripe::StripeError => e
        # Record the error but leave the item pending so it can be retried; only a
        # successful transfer flips it to paid.
        item.update!(error: e.message.to_s.truncate(500))
        failed += 1
      end

      all_paid = batch.items.where.not(status: "paid").none?
      # Keep the run open (draft) while anything's still to send, so failures can
      # be retried and later course additions accumulate into the same run.
      batch.update!(
        status: all_paid ? "completed" : "draft",
        completed_at: all_paid ? Time.current : nil
      )

      Result.new(batch: batch, paid: paid, failed: failed)
    end

    private

    # Tie the transfer back to the course and payout it settles.
    def transfer_metadata(item)
      meta = { payout_batch_item_id: item.id, kind: "course" }
      payout = course_payout_for(item)
      if payout
        meta[:course_offering_payout_id] = payout.id
        meta[:course_offering_id] = payout.course_offering_id
      end
      meta
    end

    # The organization's own remainder is recorded as an OrgPayout — the books'
    # record that CocoScout remitted the org its share.
    def record_org_payout!(item)
      return unless item.payee.is_a?(Organization)

      OrgPayout.create!(
        organization: item.payee,
        course_offering: course_payout_for(item)&.course_offering,
        amount_cents: item.amount_cents,
        status: "paid",
        payout_type: "full_course",
        payment_method: "bank_transfer",
        paid_at: Time.current
      )
    end

    def course_payout_for(item)
      source = item.payout_contributions.first&.source
      source.is_a?(CourseOfferingPayout) ? source : source.try(:course_offering_payout)
    end
  end
end
