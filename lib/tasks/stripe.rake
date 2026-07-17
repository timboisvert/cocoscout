# frozen_string_literal: true

namespace :stripe do
  desc "Create the CocoScout Pro subscription product + monthly/annual prices in Stripe (run once per environment)"
  task setup_subscription_prices: :environment do
    product = Stripe::Product.create(
      name: "CocoScout Pro",
      description: "CocoScout Pro — unlimited productions and events, plus all management modules."
    )

    monthly = Stripe::Price.create(
      product: product.id,
      unit_amount: SubscriptionPlan::PRO_MONTHLY_CENTS,
      currency: "usd",
      recurring: { interval: "month" },
      metadata: { plan: "pro", interval: "month" }
    )

    annual = Stripe::Price.create(
      product: product.id,
      unit_amount: SubscriptionPlan::PRO_ANNUAL_CENTS,
      currency: "usd",
      recurring: { interval: "year" },
      metadata: { plan: "pro", interval: "year" }
    )

    puts "\nCocoScout Pro created. Add these to your environment / credentials:"
    puts "  Product:                 #{product.id}"
    puts "  STRIPE_PRICE_PRO_MONTHLY=#{monthly.id}"
    puts "  STRIPE_PRICE_PRO_ANNUAL=#{annual.id}"
  end

  desc "Create the metered $5/active-staff meter + price (run once per environment)"
  task setup_staff_meter: :environment do
    event_name = "staff_active_monthly"

    meter = Stripe::Billing::Meter.create(
      display_name: "Active staff members",
      event_name: event_name,
      # One unit is billed per distinct active staff member per billing period.
      default_aggregation: { formula: "sum" },
      customer_mapping: { event_payload_key: "stripe_customer_id", type: "by_id" },
      value_settings: { event_payload_key: "value" }
    )

    product = Stripe::Product.create(name: "CocoScout Staffing — active staff member")
    price = Stripe::Price.create(
      product: product.id,
      currency: "usd",
      unit_amount: StaffBillingService::PER_ACTIVE_STAFF_CENTS, # $5
      recurring: { interval: "month", usage_type: "metered", meter: meter.id },
      metadata: { plan: "staff_active" }
    )

    puts "\nStaffing meter created. Add these to your environment / credentials"
    puts "(attached to the org's usage subscription so reported usage invoices):"
    puts "  STRIPE_METER_STAFF_ACTIVE=#{event_name}"
    puts "  STRIPE_PRICE_STAFF_ACTIVE=#{price.id}"
    puts "  Meter:  #{meter.id}"

    # Performer meter: $3/active performer/month (cast in a show that month).
    # Configure this alongside the staff meter so the usage subscription is
    # created carrying both prices from the first activation.
    perf_event = "performer_active_monthly"
    perf_meter = Stripe::Billing::Meter.create(
      display_name: "Active performers",
      event_name: perf_event,
      default_aggregation: { formula: "sum" },
      customer_mapping: { event_payload_key: "stripe_customer_id", type: "by_id" },
      value_settings: { event_payload_key: "value" }
    )
    perf_product = Stripe::Product.create(name: "CocoScout Money — active performer")
    perf_price = Stripe::Price.create(
      product: perf_product.id,
      currency: "usd",
      unit_amount: PerformerBillingService::PER_ACTIVE_PERFORMER_CENTS, # $3
      recurring: { interval: "month", usage_type: "metered", meter: perf_meter.id },
      metadata: { plan: "performer_active" }
    )

    puts "\nPerformer meter created:"
    puts "  STRIPE_METER_PERFORMER_ACTIVE=#{perf_event}"
    puts "  STRIPE_PRICE_PERFORMER_ACTIVE=#{perf_price.id}"
    puts "  Meter:  #{perf_meter.id}"
  end
end
