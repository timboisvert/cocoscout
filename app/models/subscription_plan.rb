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

  # Metered staffing price IDs (the $5/active-staff and $1/extra-payment prices
  # created by `rake stripe:setup_staff_meter`). When set, they're attached to
  # the Pro subscription at checkout so reported usage actually invoices.
  def staff_active_price_id
    ENV["STRIPE_PRICE_STAFF_ACTIVE"] || Rails.application.credentials.dig(:stripe, :price_staff_active)
  end

  def staff_extra_price_id
    ENV["STRIPE_PRICE_STAFF_EXTRA"] || Rails.application.credentials.dig(:stripe, :price_staff_extra)
  end

  # Checkout line items for a Pro subscription: the base plan, plus the two
  # metered staffing prices when configured. Metered prices are added without a
  # quantity — Stripe bills them from the usage the app reports. Returns nil when
  # the base plan price isn't configured.
  def checkout_line_items(interval)
    base = price_id(interval)
    return nil if base.blank?

    items = [ { price: base, quantity: 1 } ]
    items << { price: staff_active_price_id } if staff_active_price_id.present?
    items << { price: staff_extra_price_id } if staff_extra_price_id.present?
    items
  end
end
