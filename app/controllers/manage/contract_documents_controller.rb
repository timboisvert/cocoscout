# frozen_string_literal: true

module Manage
  class ContractDocumentsController < ManageController
    before_action :set_contract

    def create
      @document = @contract.contract_documents.build(document_params)

      if @document.save
        redirect_to manage_contract_path(@contract), notice: "Document uploaded."
      else
        redirect_to manage_contract_path(@contract), alert: "Could not upload document: #{@document.errors.full_messages.join(', ')}"
      end
    end

    def destroy
      @document = @contract.contract_documents.find(params[:id])
      @document.destroy
      redirect_to manage_contract_path(@contract), notice: "Document deleted."
    end

    private

    def set_contract
      @contract = Current.organization.contracts.find(params[:contract_id])
    end

    def document_params
      params.require(:contract_document).permit(:name, :document_type, :notes, :file)
    end
  end
end
