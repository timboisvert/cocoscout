# frozen_string_literal: true

module My
  class PaymentsController < ApplicationController
    before_action :require_user
    before_action :set_person

    def index
      # A simple log of everything this person has been paid, across all shows.
      paid_items = ShowPayoutLineItem
        .where(payee: @person)
        .joins(show_payout: :show)
        .where(show_payouts: { status: "paid" })
        .includes(show_payout: { show: :production })
        .order("show_payout_line_items.paid_at DESC NULLS LAST, shows.date_and_time DESC")

      @total_received = paid_items.to_a.sum(&:amount)
      # What we still owe them, across every organization (from the ledger).
      @to_be_paid_cents = @person.payout_balance_cents

      @pagy, @payment_history = pagy(paid_items, limit: 25)
    end

    def setup
      # Payment settings page: connect your bank (Stripe captures your legal name
      # during onboarding, so there's no name step here).
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
      # Keep each org's cached staff onboarding_state in step with the new bank
      # status, so "awaiting bank" clears wherever they connected it.
      OrganizationStaffMember.active.where(person_id: @person.id).find_each(&:refresh_onboarding_state!)
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
  end
end
