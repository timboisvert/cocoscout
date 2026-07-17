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

  desc "Create/reuse the metered $5/active-staff and $3/active-performer meters + prices (idempotent)"
  task setup_staff_meter: :environment do
    # Reuse an active meter with this event name if one already exists, else
    # create it. (Stripe rejects a second active meter for the same event name.)
    ensure_meter = lambda do |event_name, display_name|
      existing = Stripe::Billing::Meter.list(status: "active", limit: 100).auto_paging_each.find { |m| m.event_name == event_name }
      if existing
        puts "  reusing meter #{existing.id} (#{event_name})"
        existing
      else
        Stripe::Billing::Meter.create(
          display_name: display_name,
          event_name: event_name,
          default_aggregation: { formula: "sum" },
          customer_mapping: { event_payload_key: "stripe_customer_id", type: "by_id" },
          value_settings: { event_payload_key: "value" }
        )
      end
    end

    # Reuse the active metered price attached to this meter if one exists, else
    # create a new product + price. Keeps re-runs from stacking duplicate prices.
    ensure_price = lambda do |meter_id, unit_amount, product_name, plan|
      existing = Stripe::Price.list(active: true, type: "recurring", limit: 100).auto_paging_each.find { |p| p.recurring&.meter == meter_id }
      if existing
        puts "  reusing price #{existing.id} (#{plan})"
        existing
      else
        product = Stripe::Product.create(name: product_name)
        Stripe::Price.create(
          product: product.id,
          currency: "usd",
          unit_amount: unit_amount,
          recurring: { interval: "month", usage_type: "metered", meter: meter_id },
          metadata: { plan: plan }
        )
      end
    end

    staff_meter = ensure_meter.call("staff_active_monthly", "Active staff members")
    staff_price = ensure_price.call(staff_meter.id, StaffBillingService::PER_ACTIVE_STAFF_CENTS, "CocoScout Staffing — active staff member", "staff_active")

    perf_meter = ensure_meter.call("performer_active_monthly", "Active performers")
    perf_price = ensure_price.call(perf_meter.id, PerformerBillingService::PER_ACTIVE_PERFORMER_CENTS, "CocoScout Money — active performer", "performer_active")

    puts "\nUsage meters ready. Ensure these are in your environment / credentials"
    puts "(both prices attach to the org's usage subscription so reported usage invoices):"
    puts "  STRIPE_METER_STAFF_ACTIVE=staff_active_monthly"
    puts "  STRIPE_PRICE_STAFF_ACTIVE=#{staff_price.id}"
    puts "  STRIPE_METER_PERFORMER_ACTIVE=performer_active_monthly"
    puts "  STRIPE_PRICE_PERFORMER_ACTIVE=#{perf_price.id}"
  end
end
