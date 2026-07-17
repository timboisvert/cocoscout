# frozen_string_literal: true

# Reports performer usage to Stripe's Billing Meter Events API so orgs are billed
# $3/month per active performer — the performer analog of StaffMeterService.
#
# Each PerformerActivation (a durable, once-per-person-per-month record created
# when a performer is cast + notified) reports a single meter event of value 1.
# Because activations are unique per person/month and the event carries a stable
# `identifier`, Stripe counts each active performer exactly once — even on retry
# or nightly reconciliation.
#
# Shares the org's single usage subscription with staffing (see
# StaffMeterService#ensure_staffing_subscription! + SubscriptionPlan
# #staffing_subscription_items, which carries both metered prices). Metering
# stays OFF until STRIPE_METER_PERFORMER_ACTIVE is configured.
module PerformerMeterService
  module_function

  def active_event_name
    ENV["STRIPE_METER_PERFORMER_ACTIVE"] || Rails.application.credentials.dig(:stripe, :meter_performer_active)
  end

  def configured?
    active_event_name.present?
  end

  # Report a single active-performer unit for the activation's month.
  def report_activation!(activation)
    org = activation.organization
    return :not_configured unless configured? && org&.stripe_customer_id.present?

    StaffMeterService.ensure_staffing_subscription!(org)

    Stripe::Billing::MeterEvent.create(
      event_name: active_event_name,
      identifier: identifier_for(activation),
      payload: { stripe_customer_id: org.stripe_customer_id, value: "1" }
    )
    activation.update_column(:reported_at, Time.current)
    :reported
  rescue Stripe::StripeError => e
    Rails.logger.warn("Performer meter report failed for activation #{activation.id}: #{e.message}")
    :error
  end

  # Re-send any of an org's activations for `month` that haven't been metered yet
  # (catches events that failed to send). Idempotent thanks to the identifiers.
  def reconcile_month!(organization, month: Date.current)
    return :not_configured unless organization.stripe_customer_id.present? && configured?

    organization.performer_activations.for_month(month).where(reported_at: nil).find_each do |activation|
      report_activation!(activation)
    end
    :reconciled
  end

  def identifier_for(activation)
    "performer_active:#{activation.organization_id}:#{activation.person_id}:#{activation.billing_month.iso8601}"
  end
end
