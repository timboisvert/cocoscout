# frozen_string_literal: true

# Writing into a contract's thread (ContractThread), from the organization's
# contract page or the contract person's own. Anyone in it may write: the
# organization's owner and managers, the contractor, the people on the
# contract, and the connected organization's managers.
class ContractThreadsController < ApplicationController
  def create
    contract = Contract.find(params[:contract_id])
    return head(:not_found) unless ContractThread.can_post?(Current.user, contract)

    body = params[:body].to_s.strip
    return redirect_back(fallback_location: root_path, alert: "Write a message first.") if body.blank?

    body = [ body, *pay_link_lines(contract) ].join("\n\n")
    ContractThread.post!(contract, sender: Current.user, body: body)
    # Back to the contract page, where the card now shows it, at the same
    # scroll (found testing 1.4 from main, 2026-11-22).
    redirect_back fallback_location: root_path, notice: "Sent to everyone on the contract."
  rescue ArgumentError => e
    redirect_back fallback_location: root_path, alert: e.message
  end

  private

  # The pay links the organization's Message window offered to add: money
  # this contractor owes on this contract that can still be paid online.
  def pay_link_lines(contract)
    ids = Array(params[:pay_link_payment_ids]).map(&:to_i)
    return [] if ids.empty? || !contract.organization.manageable_by?(Current.user)

    contract.contract_payments.where(id: ids).select(&:collectable_online?).map do |payment|
      "Pay the #{ActiveSupport::NumberHelper.number_to_currency(payment.amount)} online: #{pay_contract_url(token: payment.payment_token!)}"
    end
  end
end
