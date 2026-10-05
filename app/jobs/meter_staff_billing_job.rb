# frozen_string_literal: true

# Nightly reconciliation for usage billing: cancels usage subscriptions an org
# no longer pays for, then re-sends any of this month's staff
# and performer activations that haven't been metered to Stripe yet (e.g. an
# event that failed when it was first created). Idempotent — Stripe dedupes on
# the meter event identifier, so re-running is always safe.
class MeterStaffBillingJob < ApplicationJob
  queue_as :background

  def perform
    # A usage subscription outlives its reason when an org leaves Pro or its
    # usage is comped; cancel those first, whether or not metering is on.
    Organization.where.not(staffing_subscription_id: nil).find_each do |organization|
      StaffMeterService.sync_usage_subscription!(organization)
    rescue Stripe::StripeError => e
      Rails.logger.warn("Usage subscription sync failed for org #{organization.id}: #{e.message}")
    end

    return unless StaffMeterService.configured? || PerformerMeterService.configured?

    Organization.where.not(stripe_customer_id: nil).find_each do |organization|
      StaffMeterService.reconcile_month!(organization)
      PerformerMeterService.reconcile_month!(organization)
    end
  end
end
