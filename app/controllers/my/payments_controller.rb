# frozen_string_literal: true

module My
  class PaymentsController < ApplicationController
    before_action :require_user
    before_action :set_person

    def index
      # Get all payment history for the current person across all shows
      @payment_history = ShowPayoutLineItem
        .where(payee: @person)
        .joins(show_payout: :show)
        .where(show_payouts: { status: "paid" })
        .includes(show_payout: { show: :production })
        .order("show_payout_line_items.paid_at DESC NULLS LAST, shows.date_and_time DESC")
        .limit(50)

      # Calculate totals
      @total_received = @payment_history.sum(&:amount)
      @stripe_total = @payment_history.select(&:paid_via_stripe?).sum(&:amount)
      @offline_total = @payment_history.reject(&:paid_via_stripe?).sum(&:amount)

      # Pending payouts (approved but not yet paid)
      @pending_payouts = ShowPayoutLineItem
        .where(payee: @person)
        .joins(show_payout: :show)
        .where(show_payouts: { status: "approved" })
        .where(manually_paid: false)
        .includes(show_payout: { show: :production })
        .order("shows.date_and_time DESC")
    end

    def setup
      # Page for managing Stripe Connect account
    end

    def connect_stripe
      # TODO: Implement actual Stripe Connect account creation
      # For now, just show a placeholder message
      redirect_to setup_my_payments_path, notice: "Stripe integration coming soon! We'll notify you when it's ready."
    end

    def stripe_dashboard
      # TODO: Implement Stripe dashboard link
      if @person.stripe_account_id.present?
        # Will redirect to Stripe-hosted dashboard when implemented
        redirect_to my_payments_path, notice: "Stripe dashboard link coming soon!"
      else
        redirect_to setup_my_payments_path, alert: "Please set up your payment account first."
      end
    end

    def refresh_status
      # TODO: Implement Stripe account status sync
      redirect_to my_payments_path, notice: "Payment status will be synced when Stripe is connected."
    end

    private

    def require_user
      return if Current.user

      redirect_to signin_path, alert: "Please sign in to view your payments."
    end

    def set_person
      @person = Current.user&.person
      return if @person

      redirect_to profile_path, alert: "Please complete your profile to view payments."
    end
  end
end
