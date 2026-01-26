# frozen_string_literal: true

module Manage
  class ContractPaymentsController < ManageController
    before_action :set_contract
    before_action :set_payment, only: %i[update destroy mark_paid]

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
        redirect_to manage_contract_path(@contract), notice: "Payment updated."
      else
        redirect_to manage_contract_path(@contract), alert: "Could not update payment: #{@payment.errors.full_messages.join(', ')}"
      end
    end

    def destroy
      @payment.destroy
      redirect_to manage_contract_path(@contract), notice: "Payment deleted."
    end

    def mark_paid
      @payment.mark_paid!(
        paid_on: params[:paid_date].present? ? Date.parse(params[:paid_date]) : Date.current,
        method: params[:payment_method],
        reference: params[:reference_number]
      )
      redirect_to manage_contract_path(@contract), notice: "Payment marked as paid."
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
        :description, :amount, :direction, :due_date, :notes
      )
    end
  end
end
