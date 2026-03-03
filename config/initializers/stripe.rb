# frozen_string_literal: true

Stripe.api_key = ENV["STRIPE_SECRET_KEY"] || Rails.application.credentials.dig(:stripe, :secret_key)
