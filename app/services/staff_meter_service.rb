# frozen_string_literal: true

# Reports staffing usage to Stripe's Billing Meter Events API so orgs are billed
# $5/month per active staff member on their existing Pro subscription.
#
# Each StaffActivation (a durable, once-per-person-per-month record created when
# a staffer is paid staff pay on a payout run) reports a single meter event of
# value 1.
# Because activations are unique per person/month and the event carries a stable
# `identifier`, Stripe counts each active person exactly once — even if the
# event is retried or re-sent by the nightly reconciliation.
#
# Only orgs that pay for usage are metered (Organization#bills_usage?: on Pro,
# usage not comped).
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
    return :not_billed unless org.bills_usage?

    ensure_staffing_subscription!(org)

    Stripe::Billing::MeterEvent.create(
      event_name: active_event_name,
      identifier: identifier_for(activation),
      payload: { stripe_customer_id: org.stripe_customer_id, value: "1" },
      timestamp: meter_timestamp(activation.first_notified_at)
    )
    activation.update_column(:reported_at, Time.current)
    :reported
  rescue Stripe::StripeError => e
    Rails.logger.warn("Staff meter report failed for activation #{activation.id}: #{e.message}")
    :error
  end

  # Ensure the org has its separate, always-monthly staffing subscription — the
  # one that carries the two metered prices — so reported usage actually
  # invoices, regardless of whether the Pro plan is monthly or annual. Created
  # once, lazily, on the first metered event. Best-effort: returns the
  # subscription id or nil (usage still records on the customer either way).
  def ensure_staffing_subscription!(org)
    return org.staffing_subscription_id if org.staffing_subscription_id.present?
    return nil unless org.bills_usage?

    items = SubscriptionPlan.staffing_subscription_items
    return nil if items.nil? || org.stripe_customer_id.blank?

    subscription = Stripe::Subscription.create(
      customer: org.stripe_customer_id,
      items: items,
      metadata: { organization_id: org.id, kind: "staffing" }
    )
    org.update_column(:staffing_subscription_id, subscription.id)
    subscription.id
  rescue Stripe::StripeError => e
    Rails.logger.warn("Staffing subscription create failed for org #{org.id}: #{e.message}")
    nil
  end

  # An org that no longer pays for usage (left Pro, or a superadmin comped its
  # usage) keeps no usage subscription: cancel it without a final invoice, so
  # the comp covers whatever was metered this month. Returns true if it
  # canceled one.
  def sync_usage_subscription!(org)
    return false if org.bills_usage? || org.staffing_subscription_id.blank?

    Stripe::Subscription.cancel(org.staffing_subscription_id)
    org.update_column(:staffing_subscription_id, nil)
    true
  rescue Stripe::InvalidRequestError => e
    # Already gone in Stripe: forget it here too.
    raise unless e.http_status == 404 || e.message.to_s.include?("No such subscription")

    org.update_column(:staffing_subscription_id, nil)
    true
  end

  # Re-send any of an org's activations for `month` that haven't been metered yet
  # (catches events that failed to send). Idempotent thanks to the event
  # identifiers.
  def reconcile_month!(organization, month: Date.current)
    return :not_configured unless organization.stripe_customer_id.present? && configured?
    return :not_billed unless organization.bills_usage?

    organization.staff_activations.for_month(month).where(reported_at: nil).find_each do |activation|
      report_activation!(activation)
    end
    :reconciled
  end

  # When the person became billable, so a re-send still counts in that
  # period. Stripe takes events up to 35 days old; anything older goes as now.
  def meter_timestamp(time)
    time = Time.current if time.nil? || time < 34.days.ago
    time.to_i
  end

  def identifier_for(activation)
    "staff_active:#{activation.organization_id}:#{activation.person_id}:#{activation.billing_month.iso8601}"
  end
end
