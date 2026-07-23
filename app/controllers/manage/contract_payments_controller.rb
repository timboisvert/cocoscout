# frozen_string_literal: true

module Manage
  class ContractPaymentsController < ManageController
    before_action :set_contract
    before_action :set_payment, only: %i[update destroy mark_paid add_to_payout_run]

    def create
      @payment = @contract.contract_payments.build(payment_params)

      if @payment.save
        redirect_to manage_contract_path(@contract), notice: "Payment added."
      else
        redirect_to manage_contract_path(@contract), alert: "Could not add payment: #{@payment.errors.full_messages.join(', ')}"
      end
    end

    def update
      if @payment.update(payment_params)
        redirect_back fallback_location: manage_contract_path(@contract), notice: "Payment updated."
      else
        redirect_back fallback_location: manage_contract_path(@contract), alert: "Could not update payment: #{@payment.errors.full_messages.join(', ')}"
      end
    end

    def destroy
      @payment.destroy
      redirect_to manage_contract_path(@contract), notice: "Payment deleted."
    end

    # Records money that reached us outside CocoScout (a check, a direct bank
    # transfer). Outgoing money is never marked paid by hand — it's paid through
    # the contractor payout run, which marks it paid when the transfer settles.
    def mark_paid
      unless @payment.direction_incoming?
        return redirect_back fallback_location: manage_contract_path(@contract),
                             alert: "Money you owe is paid through your payout run, not marked paid by hand."
      end

      unless @contract.offline_payments_allowed?
        return redirect_back fallback_location: manage_contract_path(@contract),
                             alert: "This contract is online payment only. Allow another method on the contract first."
      end

      method = params[:payment_method].presence
      if method.present? && !method.in?(@contract.offline_payment_methods)
        return redirect_back fallback_location: manage_contract_path(@contract),
                             alert: "This contract doesn't accept payment by #{method.humanize.downcase}."
      end

      @payment.mark_paid!(
        paid_on: params[:paid_date].present? ? Date.parse(params[:paid_date]) : Date.current,
        method: method,
        reference: params[:reference_number],
        amount: params[:payment_amount]
      )
      redirect_back fallback_location: manage_contract_path(@contract), notice: "Payment recorded."
    end

    # Add this outgoing payment to the org's open contractor payout run, to be
    # paid to the contractor's bank via Stripe (same rail as performers/staff).
    def add_to_payout_run
      result = ContractorPayoutRunService.add_contract_payment!(@payment, added_by: Current.user)
      if result.added
        redirect_to manage_payout_batch_path(result.batch),
                    notice: "Added #{@payment.contract.contractor_name} to your open payout run."
      elsif result.batch # already added
        redirect_to manage_payout_batch_path(result.batch), notice: "This payment is already in a payout run."
      else
        redirect_back fallback_location: manage_contract_path(@contract), alert: result.error
      end
    end

    private

    def set_contract
      @contract = Current.organization.contracts.find(params[:contract_id])
    end

    def set_payment
      @payment = @contract.contract_payments.find(params[:id])
    end

    def payment_params
      params.require(:contract_payment).permit(
        :description, :amount, :amount_tbd, :direction, :due_date, :notes, :show_id
      )
    end
  end
end
