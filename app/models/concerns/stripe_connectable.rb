# frozen_string_literal: true

# Payee-side Stripe Connect state. Mixed into Person and Contractor so they can
# receive real bank payouts once they've connected an Express account. Backed by
# the columns added in AddStripeConnectToPayees (stripe_account_id,
# stripe_account_status, payouts_enabled, stripe_account_synced_at).
module StripeConnectable
  extend ActiveSupport::Concern

  # A Connect account has been created (onboarding may or may not be finished).
  def connect_account_started?
    stripe_account_id.present?
  end

  # Fully onboarded and cleared by Stripe to receive payouts.
  def can_receive_payouts?
    stripe_account_id.present? && payouts_enabled?
  end

  # Still needs to connect (or finish connecting) a bank to be paid via Stripe.
  def needs_bank_connection?
    !can_receive_payouts?
  end

  def connect_status_label
    return "Not connected" unless connect_account_started?

    can_receive_payouts? ? "Connected" : "Finishing setup"
  end
end
