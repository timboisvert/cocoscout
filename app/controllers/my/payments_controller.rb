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
      @venmo_total = @payment_history.select(&:paid_via_venmo?).sum(&:amount)
      @offline_total = @payment_history.reject(&:paid_via_venmo?).sum(&:amount)

      # Pending payouts (approved but not yet paid)
      @pending_payouts = ShowPayoutLineItem
        .where(payee: @person)
        .joins(show_payout: :show)
        .where(show_payouts: { status: "approved" })
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

    def venmo_params
      params.require(:person).permit(:venmo_identifier, :venmo_identifier_type)
    end
  end
end
