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

    # GET /manage/billing/statements/:id — a monthly CocoScout statement's PDF.
    def statement
      statement = Current.organization.org_statements.find(params[:id])
      return head :not_found unless statement.pdf.attached?

      send_data statement.pdf.download, filename: statement.filename, type: "application/pdf", disposition: "inline"
    end

    # GET /manage/billing/invoices/:id — CocoScout's invoice for one bill
    # (Pro or usage), made fresh as a PDF.
    def invoice
      bill = Current.organization.billing_invoices.find(params[:id])
      send_data InvoicePdf.new(CocoScoutInvoice.document(bill)).render, filename: CocoScoutInvoice.filename(bill),
                                                                         type: "application/pdf", disposition: "inline"
    end

    # PATCH /manage/billing/contacts — who gets the bills, receipts and
    # monthly statements: ticked managers plus other addresses, one per line.
    def update_contacts
      @organization = Current.organization
      @organization.save_billing_contacts!(user_ids: params[:billing_contact_user_ids],
                                                   emails: params[:billing_contact_emails].to_s.split(/[\s,;]+/))
      redirect_to org_billing_tab_path, notice: "Saved who gets the bills."
    rescue ArgumentError => e
      redirect_to org_billing_tab_path, alert: e.message
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

      # Producer setup routes through checkout mid-flow — send those users to
      # the manage home (where the what's-next panel is) instead of billing.
      landing = session.delete(:return_to_home_after_checkout) ? manage_path : org_billing_tab_path

      if @organization.reload.on_paid_plan?
        redirect_to landing, notice: "You're on CocoScout Pro — thank you!"
      else
        redirect_to landing, notice: "Your subscription is being processed. It'll be active shortly."
      end
    end

    # POST /manage/billing/keep_pro — complimentary Pro is ending and they
    # want to stay. Monthly: Pro carries on on the monthly bill, paid from the
    # card or bank on file (or checkout saves one first); the comp's days are
    # never charged. Yearly: checkout, with the first year starting when the
    # comp ends.
    def keep_pro
      @organization = Current.organization
      return start_checkout("year") if params[:interval] == "year"
      return start_checkout("month") unless payment_method_on_file?

      @organization.start_pro_on_monthly_bill!
      from = @organization.comped? && !@organization.comped_indefinitely? ? @organization.comped_until.next_day.strftime("%B %-d") : "today"
      redirect_to org_billing_tab_path, notice: "You're keeping Pro. From #{from} it's $#{SubscriptionPlan.monthly_dollars} a month on your one monthly bill."
    end

    # POST /manage/billing/cancel_pro — end Pro paid on the monthly bill at the
    # end of this month; that month's bill is the last.
    def cancel_pro
      @organization = Current.organization
      unless @organization.pro_on_monthly_bill?
        redirect_to org_billing_tab_path, alert: "There's no monthly Pro plan to cancel." and return
      end

      @organization.cancel_pro_on_monthly_bill!
      redirect_to org_billing_tab_path, notice: "Pro is canceled. It stays on through #{@organization.pro_monthly_until.strftime('%B %-d')}, and that month's bill is the last."
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
      section_manage_organization_path(@organization, section: "billing")
    end

    def org_billing_tab_url
      section_manage_organization_url(@organization, section: "billing")
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

      # Monthly: Pro goes on the one monthly bill with the usage, so checkout
      # only saves the card or bank that bill is paid from (ProMonthlyStart).
      if interval.to_s.in?(%w[month monthly])
        session = Stripe::Checkout::Session.create(
          ProMonthlyStart.session_params(@organization, success_url: manage_billing_success_url + "?session_id={CHECKOUT_SESSION_ID}",
                                                        cancel_url: org_billing_tab_url)
        )
        redirect_to session.url, allow_other_host: true
        return
      end

      # Annual: the Pro plan on its own, paid once a year; usage still comes on
      # the monthly bill (StaffMeterService). Still on a comp, the first year
      # starts when the comp ends.
      subscription_data = { metadata: { organization_id: @organization.id } }
      comp_end = @organization.comped_indefinitely? ? nil : @organization.comped_until
      subscription_data[:trial_end] = comp_end.to_i if comp_end && comp_end > 3.days.from_now
      session = Stripe::Checkout::Session.create(
        mode: "subscription",
        customer: @organization.stripe_customer_id,
        line_items: [ { price: price_id, quantity: 1 } ],
        success_url: manage_billing_success_url + "?session_id={CHECKOUT_SESSION_ID}",
        cancel_url: org_billing_tab_url,
        metadata: { organization_id: @organization.id },
        subscription_data: subscription_data
      )

      redirect_to session.url, allow_other_host: true
    rescue Stripe::StripeError => e
      Rails.logger.error "Stripe subscription checkout failed for org #{@organization.id}: #{e.message}"
      redirect_to org_billing_tab_path, alert: "Unable to connect to our payment processor. Please try again."
    end

    # A card or bank the monthly bill can be paid from.
    def payment_method_on_file?
      return false if @organization.stripe_customer_id.blank?

      Stripe::Customer.retrieve(@organization.stripe_customer_id).invoice_settings&.default_payment_method.present?
    rescue Stripe::StripeError
      false
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
      return if ProMonthlyStart.from_session!(@organization, session)
      return if session.subscription.blank?
      return unless session.metadata["organization_id"].to_i == @organization.id

      SubscriptionSyncService.from_id(@organization, session.subscription)
    rescue Stripe::StripeError => e
      Rails.logger.error "Failed to sync subscription from session #{session_id}: #{e.message}"
    end
  end
end
