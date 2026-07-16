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

  # Separate meter for the $1-per-extra-payment fees (2 free payments/month per
  # staff member, then $1 each).
  def extra_payment_event_name
    ENV["STRIPE_METER_STAFF_EXTRA"] || Rails.application.credentials.dig(:stripe, :meter_staff_extra)
  end

  def configured?
    active_event_name.present?
  end

  def extra_payments_configured?
    extra_payment_event_name.present?
  end

  # Report a single active-staff-member unit for the activation's month.
  def report_activation!(activation)
    org = activation.organization
    return :not_configured unless configured? && org&.stripe_customer_id.present?

    ensure_staffing_subscription!(org)

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

  # Ensure the org has its separate, always-monthly staffing subscription — the
  # one that carries the two metered prices — so reported usage actually
  # invoices, regardless of whether the Pro plan is monthly or annual. Created
  # once, lazily, on the first metered event. Best-effort: returns the
  # subscription id or nil (usage still records on the customer either way).
  def ensure_staffing_subscription!(org)
    return org.staffing_subscription_id if org.staffing_subscription_id.present?

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

  # Report the $1 extra-payment fees from a pay run as metered units (one unit =
  # $1). Idempotent per batch.
  def report_extra_payments!(batch)
    org = batch.organization
    units = batch.extra_payment_fee_cents.to_i / 100
    return :nothing_to_report if units <= 0
    return :not_configured unless extra_payments_configured? && org&.stripe_customer_id.present?

    ensure_staffing_subscription!(org)

    Stripe::Billing::MeterEvent.create(
      event_name: extra_payment_event_name,
      identifier: "staff_extra:batch:#{batch.id}",
      payload: { stripe_customer_id: org.stripe_customer_id, value: units.to_s }
    )
    batch.update_column(:fee_metered_at, Time.current)
    :reported
  rescue Stripe::StripeError => e
    Rails.logger.warn("Staff extra-payment meter failed for batch #{batch.id}: #{e.message}")
    :error
  end

  # Re-send any of an org's activations + pay-run fees for `month` that haven't
  # been metered yet (catches events that failed to send). Idempotent thanks to
  # the event identifiers.
  def reconcile_month!(organization, month: Date.current)
    return :not_configured unless organization.stripe_customer_id.present?

    if configured?
      organization.staff_activations.for_month(month).where(reported_at: nil).find_each do |activation|
        report_activation!(activation)
      end
    end

    if extra_payments_configured?
      range = month.to_date.beginning_of_month.beginning_of_day..month.to_date.end_of_month.end_of_day
      organization.payout_batches.where(created_at: range, fee_metered_at: nil)
                  .where("extra_payment_fee_cents > 0").find_each do |batch|
        report_extra_payments!(batch)
      end
    end
    :reconciled
  end

  def identifier_for(activation)
    "staff_active:#{activation.organization_id}:#{activation.person_id}:#{activation.billing_month.iso8601}"
  end
end
