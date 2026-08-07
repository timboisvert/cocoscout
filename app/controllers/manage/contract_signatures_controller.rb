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
      unless @contract.revoke_signing!
        redirect_to manage_contract_path(@contract), alert: "This contract isn't out for signature." and return
      end

      # Withdrawing a request that carried an amendment: the changes are still
      # staged and re-sending is one click, unless they explicitly discard —
      # nobody should have to re-enter a whole amendment because a counterparty
      # went quiet.
      if params[:discard_amendment] == "1" && @contract.amendment_pending?
        @contract.current_version.destroy!
        @contract.clear_amend_data
        redirect_to manage_contract_path(@contract),
                    notice: "Request withdrawn and the amendment discarded. The contract is unchanged." and return
      end

      notice = if @contract.amendment_pending?
                 "Request withdrawn. The amendment is still staged — sign and send it again when you're ready."
      else
                 "Signature request revoked. You can edit and re-send it."
      end
      redirect_to manage_contract_path(@contract), notice: notice
    end

    private

    def set_contract
      @contract = Current.organization.contracts.find(params[:contract_id])
    end
  end
end
