# frozen_string_literal: true

# Configuration for the CocoScout Pro subscription. Stripe Price
# IDs are stored in ENV / credentials (created once via
# `rake stripe:setup_subscription_prices`); the cent amounts here are for display
# and for creating those prices.
module SubscriptionPlan
  PRO_MONTHLY_CENTS = 2000  # $20 / month
  PRO_ANNUAL_CENTS  = 20000 # $200 / year

  module_function

  # Stripe Price ID for a given billing interval ("month" or "year").
  def price_id(interval)
    case interval.to_s
    when "month", "monthly"
      monthly_price_id
    when "year", "yearly", "annual", "annually"
      annual_price_id
    end
  end

  def monthly_price_id
    ENV["STRIPE_PRICE_PRO_MONTHLY"] || Rails.application.credentials.dig(:stripe, :price_pro_monthly)
  end

  def annual_price_id
    ENV["STRIPE_PRICE_PRO_ANNUAL"] || Rails.application.credentials.dig(:stripe, :price_pro_annual)
  end
end
