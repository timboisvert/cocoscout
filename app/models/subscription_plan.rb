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

  # Metered usage price IDs (created by `rake stripe:setup_staff_meter`):
  # $5/active-staff and $3/active-performer per month. When set, they're attached
  # to the org's usage subscription so reported usage actually invoices.
  def staff_active_price_id
    ENV["STRIPE_PRICE_STAFF_ACTIVE"] || Rails.application.credentials.dig(:stripe, :price_staff_active)
  end

  def performer_active_price_id
    ENV["STRIPE_PRICE_PERFORMER_ACTIVE"] || Rails.application.credentials.dig(:stripe, :price_performer_active)
  end

  # Subscription items for the separate, always-monthly usage subscription (the
  # metered active-staff and active-performer prices, added without a quantity —
  # Stripe bills them from reported usage). Includes each configured price;
  # returns nil if none are configured. Both meters should be configured together
  # so the subscription is created carrying both from the first activation.
  def staffing_subscription_items
    items = []
    items << { price: staff_active_price_id } if staff_active_price_id.present?
    items << { price: performer_active_price_id } if performer_active_price_id.present?
    items.presence
  end
end
