# frozen_string_literal: true

module Manage
  # Appendixes on a contract — titled rich-text sections rendered at the end of
  # the document, above the signatures, and part of what gets signed.
  #
  # Managed from the Prepare step. Once a version has been signed, its text is
  # frozen in that version's snapshot, so editing here only ever affects the
  # document going forward — never one somebody already signed.
  class ContractAppendixesController < ManageController
    before_action :set_contract
    before_action :set_appendix, only: %i[update destroy]

    def create
      appendix = @contract.contract_appendixes.new(appendix_params)
      appendix.position = (@contract.contract_appendixes.maximum(:position) || -1) + 1

      if appendix.save
        redirect_to return_path, notice: "#{appendix.heading} added."
      else
        redirect_to return_path, alert: appendix.errors.full_messages.to_sentence
      end
    end

    def update
      if @appendix.update(appendix_params)
        redirect_to return_path, notice: "#{@appendix.heading} updated."
      else
        redirect_to return_path, alert: @appendix.errors.full_messages.to_sentence
      end
    end

    def destroy
      heading = @appendix.heading
      @appendix.destroy!
      # Re-letter what's left so there's never a gap (B, C with no A).
      @contract.contract_appendixes.ordered.each_with_index do |appendix, index|
        appendix.update_column(:position, index)
      end
      redirect_to return_path, notice: "#{heading} removed."
    end

    private

    def set_contract
      @contract = Current.organization.contracts.find(params[:contract_id])
    end

    def set_appendix
      @appendix = @contract.contract_appendixes.find(params[:id])
    end

    def appendix_params
      params.require(:contract_appendix).permit(:title, :body)
    end

    # Back where they were — Prepare during the wizard, the contract otherwise.
    def return_path
      if params[:return_to] == "prepare"
        manage_prepare_contract_wizard_path(@contract)
      else
        manage_contract_path(@contract)
      end
    end
  end
end
