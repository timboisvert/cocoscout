# frozen_string_literal: true

module Manage
  # Producer side of native signing: revoke a sent-but-unsigned request. Preparing,
  # signing (org side), and sending all happen in the contract wizard's
  # Prepare → Sign → Send steps; the counterparty signs on the public
  # ContractSigningController.
  class ContractSignaturesController < ManageController
    before_action :set_contract

    # Revoke an outstanding request — kills the link; keeps the org's signature so
    # it drops back to "ready to send".
    def destroy
      if @contract.revoke_signing!
        redirect_to manage_contract_path(@contract), notice: "Signature request revoked. You can edit and re-send it."
      else
        redirect_to manage_contract_path(@contract), alert: "This contract isn't out for signature."
      end
    end

    private

    def set_contract
      @contract = Current.organization.contracts.find(params[:contract_id])
    end
  end
end
