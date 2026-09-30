# frozen_string_literal: true

# Folds an org's open draft payout runs into ONE — the oldest — from before
# the runs merged, when an org could hold an open performer run and an open
# staff run side by side. Mechanical: lines move, nothing is re-derived.
#
# For each newer draft: every contribution moves onto the survivor, onto the
# payee's item there (created if they had none); staff hours tied to the
# donor move too; then the emptied donor items and run are deleted and each
# touched item re-settles. Ledger entries are sourced on contributions (which
# keep their ids) and drafts have posted no payouts, so the ledger is
# untouched. Idempotent: an org with one open draft is left alone.
class PayoutDraftFolder
  Result = Struct.new(:organization, :survivor, :folded, keyword_init: true)

  def self.fold_all!
    PayoutBatch.where(kind: PayoutBatch::OPEN_KINDS).open_runs
               .group(:organization_id).having("COUNT(*) > 1").count.keys
               .filter_map { |org_id| fold!(Organization.find(org_id)) }
  end

  def self.fold!(organization)
    drafts = organization.payout_batches.where(kind: PayoutBatch::OPEN_KINDS).open_runs.order(:created_at, :id).to_a
    return nil if drafts.size < 2

    survivor = drafts.first
    folded = 0
    ActiveRecord::Base.transaction do
      drafts.drop(1).each do |donor|
        touched = []
        donor.items.includes(:payout_contributions).find_each do |donor_item|
          item = survivor.items.find_by(payee_type: donor_item.payee_type, payee_id: donor_item.payee_id) ||
                 survivor.items.create!(payee: donor_item.payee, amount_cents: [ donor_item.amount_cents, 1 ].max, status: "pending")
          PayoutContribution.where(payout_batch_item_id: donor_item.id)
                            .update_all(payout_batch_id: survivor.id, payout_batch_item_id: item.id, updated_at: Time.current)
          touched << item
        end
        StaffTimeEntry.where(payout_batch_id: donor.id).update_all(payout_batch_id: survivor.id, updated_at: Time.current)
        survivor.update!(payday: donor.payday) if survivor.payday.blank? && donor.payday.present?

        # Nothing hangs off the donor any more; delete without callbacks so no
        # cascade reaches the contributions that just moved.
        PayoutBatchItem.where(payout_batch_id: donor.id).delete_all
        donor.delete
        touched.uniq.each { |item| item.reload.settle_amount! }
        folded += 1
      end
      survivor.recalculate_total!
    end
    Result.new(organization: organization, survivor: survivor, folded: folded)
  end
end
