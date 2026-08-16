# frozen_string_literal: true

module Manage
  class ContractPaymentsController < ManageController
    before_action :set_contract
    before_action :set_payment, only: %i[update destroy mark_paid pay_offline add_to_payout_run settlement]

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

    # Records money we paid them outside CocoScout — Zelle, a check, cash. The
    # payout run is the normal rail, but it only reaches someone who's connected
    # a bank, and the people who haven't are exactly the ones who get paid by
    # hand. The org has to have turned the method on in Money settings first.
    def pay_offline
      unless @payment.direction_outgoing?
        return redirect_back fallback_location: manage_contract_path(@contract),
                             alert: "Money they owe you is recorded from its Collect page, not here."
      end

      unless @payment.status_pending?
        return redirect_back fallback_location: manage_contract_path(@contract),
                             alert: "This payment is already settled."
      end

      if @payment.in_payout_run?
        return redirect_back fallback_location: manage_contract_path(@contract),
                             alert: "This payment is in a payout run. Take it off the run first, then record how you paid it."
      end

      if @payment.amount_tbd? || !@payment.amount.to_f.positive?
        return redirect_back fallback_location: manage_contract_path(@contract),
                             alert: "Set an amount on this payment before recording how you paid it."
      end

      method = params[:payment_method].to_s
      choices = Current.organization.offline_payout_method_choices
      unless method.in?(choices)
        alert = choices.any? ?
          "#{Current.organization.name} doesn't pay people by #{method.humanize.downcase}." :
          "Turn on the ways you pay people outside CocoScout in Money settings first."
        return redirect_back fallback_location: manage_contract_path(@contract), alert: alert
      end

      deductions = deductible_services(@payment)
      net = @payment.amount.to_f - deductions.sum { |d| d.amount.to_f }
      if net <= 0
        return redirect_back fallback_location: manage_contract_path(@contract),
                             alert: "Their services come to at least as much as this payment, so there's nothing to hand over. Settle it through a payout run, which records the offset."
      end

      @payment.pay_offline!(
        method: method,
        paid_on: params[:paid_date].present? ? Date.parse(params[:paid_date]) : Date.current,
        reference: params[:payment_notes].presence,
        deductions: deductions
      )

      notice = "Recorded #{helpers.number_to_currency(net)} paid to #{@contract.contractor_name}."
      notice += " #{helpers.pluralize(deductions.size, 'service charge')} netted out of it." if deductions.any?
      redirect_back fallback_location: manage_contract_path(@contract), notice: notice
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

    # Flip how an incoming payment settles: they pay it directly, or it's
    # deducted from their payout when their share joins a run. Pending incoming
    # payments only — once money moved, the story is written.
    def settlement
      unless @payment.direction_incoming? && @payment.status_pending?
        redirect_back fallback_location: manage_contract_path(@contract),
                      alert: "Only a pending payment they owe can change how it's settled." and return
      end

      method = params[:settlement_method].to_s
      unless ContractPayment::SETTLEMENT_METHODS.include?(method)
        redirect_back fallback_location: manage_contract_path(@contract), alert: "Unknown settlement method." and return
      end

      # Deducting needs a payout to deduct from. On a deal where money only ever
      # comes in, this would settle nothing and leave the charge uncollectable.
      if method == "payout_deduction" && !@contract.outgoing_settlement?
        redirect_back fallback_location: manage_contract_path(@contract),
                      alert: "This contract has no payout to deduct from — nothing here goes out to them." and return
      end

      @payment.update!(settlement_method: method)
      notice = method == "payout_deduction" ?
        "#{@payment.description.presence || 'This payment'} will be deducted from their payout." :
        "#{@payment.description.presence || 'This payment'} is back to being paid directly."
      redirect_back fallback_location: manage_contract_path(@contract), notice: notice
    end

    private

    # The service charges this payment is shown netting out of on the contract
    # page — the same grouping the manager saw, so what settles matches what the
    # row said would settle (see Contract#payment_schedule_groups).
    def deductible_services(payment)
      group = @contract.payment_schedule_groups.detect { |g| g[:payment].id == payment.id }
      Array(group && group[:deductions]).select { |c| c.status_pending? && c.deduct_from_payout? }
    end

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
