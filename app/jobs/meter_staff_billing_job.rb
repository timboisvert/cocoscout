# frozen_string_literal: true

# Nightly reconciliation for staffing usage billing: re-sends any of this
# month's staff activations that haven't been metered to Stripe yet (e.g. an
# event that failed when it was first created). Idempotent — Stripe dedupes on
# the meter event identifier, so re-running is always safe.
class MeterStaffBillingJob < ApplicationJob
  queue_as :background

  def perform
    return unless StaffMeterService.configured? || StaffMeterService.extra_payments_configured?

    Organization.where.not(stripe_customer_id: nil).find_each do |organization|
      StaffMeterService.reconcile_month!(organization)
    end
  end
end
