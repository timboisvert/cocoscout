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
end
