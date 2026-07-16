# frozen_string_literal: true

module Manage
  # Self-serve subscription management for an organization: view the current
  # plan, start a Stripe Checkout to upgrade to Pro, and open the Stripe billing
  # portal to manage/cancel. Restricted to org owners and managers.
  class BillingController < ManageController
    # #upgrade is informational (the modal explaining a locked feature) — any team
    # member can view it; only owners/managers can actually check out.
    before_action :ensure_org_owner_or_manager, except: :upgrade

    # GET /manage/billing/upgrade/:feature — rich upgrade content for the modal
    # (rendered bare, no layout, for fetch injection).
    def upgrade
      @paywall_feature = params[:feature].to_s.to_sym
      @paywall = Manage::PaidFeatureGate::FEATURE_DETAILS[@paywall_feature]
      return head :not_found if @paywall.nil?

      render partial: "manage/billing/upgrade",
             locals: { paywall: @paywall, feature: @paywall_feature },
             layout: false
    end

    # There is no standalone billing page — billing lives in the Organization's
    # "Billing & Plan" tab. This route only survives to (a) kick straight into
    # checkout when arriving from the org-creation "choose Pro" flow, and
    # (b) redirect any stray links to the canonical tab.
    def show
      @organization = Current.organization

      if params[:upgrade].present? && !@organization.on_paid_plan?
        start_checkout(params[:upgrade])
      else
        redirect_to org_billing_tab_path
      end
    end

    # POST /manage/billing/checkout — start a subscription Checkout Session.
    def checkout
      @organization = Current.organization
      start_checkout(params[:interval])
    end

    # GET /manage/billing/success — Stripe redirects here after checkout. Sync
    # immediately as a fallback in case the webhook hasn't landed yet.
    def success
      @organization = Current.organization
      sync_from_checkout_session(params[:session_id]) if params[:session_id].present?

      if @organization.reload.on_paid_plan?
        redirect_to org_billing_tab_path, notice: "You're on CocoScout Pro — thank you!"
      else
        redirect_to org_billing_tab_path, notice: "Your subscription is being processed. It'll be active shortly."
      end
    end

    # POST /manage/billing/portal — open the Stripe-hosted billing portal.
    def portal
      @organization = Current.organization

      if @organization.stripe_customer_id.blank?
        redirect_to org_billing_tab_path, alert: "There's no billing account for this organization yet." and return
      end

      session = Stripe::BillingPortal::Session.create(
        customer: @organization.stripe_customer_id,
        return_url: org_billing_tab_url
      )

      redirect_to session.url, allow_other_host: true
    rescue Stripe::StripeError => e
      Rails.logger.error "Stripe billing portal failed for org #{@organization.id}: #{e.message}"
      redirect_to org_billing_tab_path, alert: "Unable to open the billing portal. Please try again."
    end

    private

    # Canonical billing location: the org's "Billing & Plan" tab (index 4).
    def org_billing_tab_path
      manage_organization_path(@organization, anchor: "tab-4")
    end

    def org_billing_tab_url
      manage_organization_url(@organization, anchor: "tab-4")
    end

    # Create a subscription Checkout Session for the given interval and redirect
    # to Stripe. Shared by the checkout action and the auto-upgrade path in show.
    def start_checkout(interval)
      price_id = SubscriptionPlan.price_id(interval)

      if price_id.blank?
        redirect_to org_billing_tab_path, alert: "That plan isn't available right now."
        return
      end

      ensure_stripe_customer!

      # Just the Pro base plan. Metered staffing usage bills on a separate
      # monthly subscription (see StaffMeterService), so it works the same for
      # annual and monthly subscribers.
      session = Stripe::Checkout::Session.create(
        mode: "subscription",
        customer: @organization.stripe_customer_id,
        line_items: [ { price: price_id, quantity: 1 } ],
        success_url: manage_billing_success_url + "?session_id={CHECKOUT_SESSION_ID}",
        cancel_url: org_billing_tab_url,
        metadata: { organization_id: @organization.id },
        subscription_data: { metadata: { organization_id: @organization.id } }
      )

      redirect_to session.url, allow_other_host: true
    rescue Stripe::StripeError => e
      Rails.logger.error "Stripe subscription checkout failed for org #{@organization.id}: #{e.message}"
      redirect_to org_billing_tab_path, alert: "Unable to connect to our payment processor. Please try again."
    end

    def ensure_stripe_customer!
      return if @organization.stripe_customer_id.present?

      customer = Stripe::Customer.create(
        name: @organization.name,
        email: Current.user.email_address,
        metadata: { organization_id: @organization.id }
      )
      @organization.update!(stripe_customer_id: customer.id)
    end

    def sync_from_checkout_session(session_id)
      session = Stripe::Checkout::Session.retrieve(session_id)
      return if session.subscription.blank?
      return unless session.metadata["organization_id"].to_i == @organization.id

      SubscriptionSyncService.from_id(@organization, session.subscription)
    rescue Stripe::StripeError => e
      Rails.logger.error "Failed to sync subscription from session #{session_id}: #{e.message}"
    end
  end
end
