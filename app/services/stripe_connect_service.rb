# frozen_string_literal: true

# Manages a payee's Stripe Connect Express account — the rail CocoScout uses to
# pay performers and staff to their bank. Mirrors the direct-Stripe-call style of
# SubscriptionSyncService / CourseOfferingStripeService.
#
#   svc = StripeConnectService.new(person)
#   svc.ensure_account                       # create the Express account if missing
#   svc.onboarding_link(return_url:, refresh_url:)  # hosted onboarding (bank + KYC)
#   svc.sync_account                         # refresh payouts_enabled/status from Stripe
#
# Stripe collects the worker's identity/tax info (incl. SSN) during onboarding —
# CocoScout never stores it.
class StripeConnectService
  class Error < StandardError; end

  def initialize(payee)
    @payee = payee
  end

  # Create the Express account if the payee doesn't have one yet. Idempotent.
  def ensure_account
    return @payee if @payee.stripe_account_id.present?

    account = Stripe::Account.create(account_params)
    @payee.update!(stripe_account_id: account.id, stripe_account_status: "pending", stripe_account_synced_at: Time.current)
    @payee
  rescue Stripe::StripeError => e
    raise Error, e.message
  end

  # An Organization is a business receiving its own revenue; Person/Contractor are
  # individuals paid for work. Only the business_type/profile differ.
  def account_params
    if org_payee?
      {
        type: "express",
        email: @payee.email.presence,
        business_type: "company",
        business_profile: {
          mcc: "7929",
          product_description: "Revenue from events, classes, and productions run through CocoScout."
        },
        company: { name: @payee.try(:name).presence }.compact,
        capabilities: { transfers: { requested: true } },
        metadata: { payee_type: @payee.class.name, payee_id: @payee.id }
      }.compact
    else
      {
        type: "express",
        email: @payee.email.presence,
        business_type: "individual",
        # These payees are individuals (performers, staff) paid small amounts, not
        # businesses. Describing the work up front means Stripe doesn't ask them
        # for a business website — onboarding is just their legal name + bank.
        business_profile: {
          mcc: "7929",
          product_description: "Payments for performing and event/staffing work booked through CocoScout."
        },
        individual: individual_prefill,
        capabilities: { transfers: { requested: true } },
        metadata: { payee_type: @payee.class.name, payee_id: @payee.id }
      }.compact
    end
  end

  def org_payee?
    @payee.is_a?(Organization)
  end

  # Prefill the individual's legal name (and email) so they don't retype it.
  def individual_prefill
    name = @payee.try(:name).to_s.strip
    first, *rest = name.split(/\s+/)
    { first_name: first.presence, last_name: rest.join(" ").presence, email: @payee.email.presence }.compact
  end

  # A single-use hosted-onboarding link. Send the payee here to connect their bank.
  # collection_options limits onboarding to what's strictly required *right now*
  # for an individual with the transfers capability (legal name + bank), and omits
  # future/eventually-due prompts — so payees aren't asked for a business name or
  # website they don't have. (Platform-wide field collection can also be trimmed
  # in Stripe Dashboard → Settings → Connect → Onboarding.)
  def onboarding_link(return_url:, refresh_url:)
    ensure_account
    Stripe::AccountLink.create(
      account: @payee.stripe_account_id,
      return_url: return_url,
      refresh_url: refresh_url,
      type: "account_onboarding",
      collection_options: { fields: "currently_due", future_requirements: "omit" }
    ).url
  rescue Stripe::StripeError => e
    raise Error, e.message
  end

  # Pull the current account state from Stripe into our columns. Pass a Stripe
  # Account (e.g. from an account.updated webhook) to avoid a re-fetch.
  def sync_account(stripe_account = nil)
    return @payee if @payee.stripe_account_id.blank?

    account = stripe_account || Stripe::Account.retrieve(@payee.stripe_account_id)
    @payee.update!(
      payouts_enabled: account.payouts_enabled,
      stripe_account_status: derive_status(account),
      stripe_account_synced_at: Time.current
    )
    @payee
  rescue Stripe::StripeError => e
    raise Error, e.message
  end

  # Find the payee behind a Connect account id (for webhooks). Checks people,
  # contractors, then organizations.
  def self.payee_for_account(account_id)
    Person.find_by(stripe_account_id: account_id) ||
      Contractor.find_by(stripe_account_id: account_id) ||
      Organization.find_by(stripe_account_id: account_id)
  end

  private

  def derive_status(account)
    return "enabled" if account.payouts_enabled
    return "restricted" if account.requirements&.disabled_reason.present?

    "pending"
  end
end
