# frozen_string_literal: true

class ContractCompletionJob < ApplicationJob
  queue_as :default

  # This job runs daily (configured in recurring.yml)
  # It auto-completes contracts that have ended and archives their associated productions.
  #
  # A contract is auto-completed when:
  # 1. It has status "active"
  # 2. Its contract_end_date is in the past
  # 3. All contract_payments are either "paid" or "waived" (no pending/overdue)
  #
  # When a contract is completed:
  # 1. Contract status changes to "completed"
  # 2. Associated productions are archived (archived_at is set)
  def perform
    completed_count = 0
    skipped_count = 0

    Contract.status_active.where("contract_end_date < ?", Date.current).find_each do |contract|
      if can_auto_complete?(contract)
        complete_contract_and_archive_productions(contract)
        completed_count += 1
        Rails.logger.info "[ContractCompletionJob] Auto-completed contract #{contract.id} (#{contract.contractor_name})"
      else
        skipped_count += 1
        Rails.logger.debug "[ContractCompletionJob] Skipped contract #{contract.id} - has unpaid payments"
      end
    end

    Rails.logger.info "[ContractCompletionJob] Completed #{completed_count} contracts, skipped #{skipped_count}"
  end

  private

  def can_auto_complete?(contract)
    # All payments must be paid or waived - no pending payments
    !contract.contract_payments.where(status: %w[pending overdue]).exists?
  end

  def complete_contract_and_archive_productions(contract)
    Contract.transaction do
      # Mark contract as completed
      contract.update!(
        status: :completed,
        completed_at: Time.current
      )

      # Archive associated productions — but never course productions,
      # since a completed instructor contract doesn't mean the course record should disappear.
      contract.productions.where(archived_at: nil)
                          .where.not(production_type: "course")
                          .update_all(archived_at: Time.current)
    end
  end
end
