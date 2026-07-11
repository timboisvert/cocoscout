# frozen_string_literal: true

# Reports staffing usage to Stripe's Billing Meter Events API so orgs are billed
# $5/month per active staff member on their existing Pro subscription.
#
# Each StaffActivation (a durable, once-per-person-per-month record created when
# a staffer is notified of a shift) reports a single meter event of value 1.
# Because activations are unique per person/month and the event carries a stable
# `identifier`, Stripe counts each active person exactly once — even if the
# event is retried or re-sent by the nightly reconciliation.
#
# Metering stays OFF until the meter's event name is configured (via
# STRIPE_METER_STAFF_ACTIVE / credentials), so nothing bills before the Stripe
# meter + $5 metered price are set up and attached to orgs' subscriptions.
module StaffMeterService
  module_function

  def active_event_name
    ENV["STRIPE_METER_STAFF_ACTIVE"] || Rails.application.credentials.dig(:stripe, :meter_staff_active)
  end

  def configured?
    active_event_name.present?
  end

  # Report a single active-staff-member unit for the activation's month.
  def report_activation!(activation)
    org = activation.organization
    return :not_configured unless configured? && org&.stripe_customer_id.present?

    Stripe::Billing::MeterEvent.create(
      event_name: active_event_name,
      identifier: identifier_for(activation),
      payload: { stripe_customer_id: org.stripe_customer_id, value: "1" }
    )
    activation.update_column(:reported_at, Time.current)
    :reported
  rescue Stripe::StripeError => e
    Rails.logger.warn("Staff meter report failed for activation #{activation.id}: #{e.message}")
    :error
  end

  # Re-send any of an org's activations for `month` that haven't been metered yet
  # (catches events that failed to send). Idempotent thanks to the identifier.
  def reconcile_month!(organization, month: Date.current)
    return :not_configured unless configured? && organization.stripe_customer_id.present?

    organization.staff_activations.for_month(month).where(reported_at: nil).find_each do |activation|
      report_activation!(activation)
    end
    :reconciled
  end

  def identifier_for(activation)
    "staff_active:#{activation.organization_id}:#{activation.person_id}:#{activation.billing_month.iso8601}"
  end
end
