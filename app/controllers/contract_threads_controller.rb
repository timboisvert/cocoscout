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

    ContractThread.post!(contract, sender: Current.user, body: body)
    # Back to the contract page, where the card now shows it, at the same
    # scroll (found testing 1.4 from main, 2026-11-22).
    redirect_back fallback_location: root_path, notice: "Sent to everyone on the contract."
  rescue ArgumentError => e
    redirect_back fallback_location: root_path, alert: e.message
  end
end
