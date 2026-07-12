# frozen_string_literal: true

# Runs an org's automatic payout for its cadence: builds a batch of everyone
# with a connected bank + positive balance and funds it, exactly like the manual
# "Run payout" flow but triggered by the schedule. Safe to call daily — it only
# acts on the org's payout day and records last_auto_payout_on so it never
# double-runs.
class ScheduledPayoutService
  Result = Struct.new(:ran, :batch, :reason, keyword_init: true)

  def self.run_due!(organization, on: Date.current)
    return Result.new(ran: false, reason: :not_due) unless organization.due_for_scheduled_payout?(on: on)

    batch = PayoutBatchService.build_for(organization: organization, created_by: nil, trigger: "scheduled")

    if batch.items.empty?
      batch.destroy
      # Mark the day handled so we don't keep rebuilding an empty batch today.
      organization.update_column(:last_auto_payout_on, on)
      return Result.new(ran: false, reason: :nothing_to_pay)
    end

    PayoutBatchService.fund!(batch, method: organization.payout_funding_method)
    organization.update_column(:last_auto_payout_on, on)
    Result.new(ran: true, batch: batch)
  rescue PayoutBatchService::Error => e
    Rails.logger.warn("Scheduled payout failed for org #{organization.id}: #{e.message}")
    Result.new(ran: false, reason: :error)
  end
end
