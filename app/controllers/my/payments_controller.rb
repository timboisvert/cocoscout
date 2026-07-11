# frozen_string_literal: true

module My
  class PaymentsController < ApplicationController
    before_action :require_user
    before_action :set_person

    def index
      # Get all payment history for the current person across all shows
      paid_items = ShowPayoutLineItem
        .where(payee: @person)
        .joins(show_payout: :show)
        .where(show_payouts: { status: "paid" })
        .includes(show_payout: { show: :production })
        .order("show_payout_line_items.paid_at DESC NULLS LAST, shows.date_and_time DESC")

      # Calculate totals from full dataset
      all_items = paid_items.to_a
      @total_received = all_items.sum(&:amount)
      @venmo_total = all_items.select(&:paid_via_venmo?).sum(&:amount)
      @zelle_total = all_items.select(&:paid_via_zelle?).sum(&:amount)
      @offline_total = all_items.reject { |p| p.paid_via_venmo? || p.paid_via_zelle? }.sum(&:amount)

      # Paginate
      @pagy, @payment_history = pagy(paid_items, limit: 25)

      # Pending payouts (awaiting payout but not yet paid)
      @pending_payouts = ShowPayoutLineItem
        .where(payee: @person)
        .joins(show_payout: :show)
        .where(show_payouts: { status: "awaiting_payout" })
        .where(manually_paid: false)
        .where(payout_reference_id: nil)
        .includes(show_payout: { show: :production })
        .order("shows.date_and_time DESC")
    end

    def setup
      # Page for managing Venmo settings
    end

    def update_venmo
      if @person.update(venmo_params)
        @person.update(venmo_verified_at: Time.current) if @person.venmo_identifier.present?
        redirect_to my_payments_setup_path, notice: "Venmo settings saved successfully!"
      else
        flash.now[:alert] = "Please fix the errors below."
        render :setup, status: :unprocessable_entity
      end
    end

    def remove_venmo
      @person.update!(
        venmo_identifier: nil,
        venmo_identifier_type: nil,
        venmo_verified_at: nil
      )
      redirect_to my_payments_setup_path, notice: "Venmo information removed."
    end

    def update_zelle
      if @person.update(zelle_params)
        @person.update(zelle_verified_at: Time.current) if @person.zelle_identifier.present?
        redirect_to my_payments_setup_path, notice: "Zelle settings saved successfully!"
      else
        flash.now[:alert] = "Please fix the errors below."
        render :setup, status: :unprocessable_entity
      end
    end

    def remove_zelle
      @person.update!(
        zelle_identifier: nil,
        zelle_identifier_type: nil,
        zelle_verified_at: nil
      )
      # If Zelle was preferred, switch to venmo if available
      if @person.preferred_payment_method == "zelle"
        @person.update!(preferred_payment_method: @person.venmo_configured? ? "venmo" : nil)
      end
      redirect_to my_payments_setup_path, notice: "Zelle information removed."
    end

    def update_preferred
      if @person.update(preferred_payment_method: params[:preferred_payment_method])
        redirect_to my_payments_setup_path, notice: "Payment preference saved!"
      else
        redirect_to my_payments_setup_path, alert: "Could not update preference."
      end
    end

    # Start (or resume) Stripe Connect bank onboarding.
    def connect_bank
      start_bank_onboarding
    end

    # Stripe redirects here when the onboarding link expires — hand back a fresh one.
    def connect_refresh
      start_bank_onboarding
    end

    # Stripe redirects here after the worker finishes (or exits) onboarding.
    def connect_return
      StripeConnectService.new(@person).sync_account
      notice = if @person.can_receive_payouts?
        "Your bank is connected — you're all set to get paid directly."
      else
        "Almost there — finish the remaining steps so you can get paid to your bank."
      end
      redirect_to my_payments_setup_path, notice: notice
    rescue StripeConnectService::Error
      redirect_to my_payments_setup_path, alert: "We couldn't confirm your bank setup. Please try again."
    end

    private

    def start_bank_onboarding
      url = StripeConnectService.new(@person).onboarding_link(
        return_url: my_payments_connect_return_url,
        refresh_url: my_payments_connect_refresh_url
      )
      redirect_to url, allow_other_host: true
    rescue StripeConnectService::Error => e
      redirect_to my_payments_setup_path, alert: "Couldn't start bank setup: #{e.message}"
    end

    def require_user
      return if Current.user

      redirect_to signin_path, alert: "Please sign in to view your payments."
    end

    def set_person
      @person = Current.user&.person
      return if @person

      redirect_to profile_path, alert: "Please complete your profile to view payments."
    end

    def venmo_params
      params.require(:person).permit(:venmo_identifier, :venmo_identifier_type)
    end

    def zelle_params
      params.require(:person).permit(:zelle_identifier, :zelle_identifier_type)
    end
  end
end
