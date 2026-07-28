# frozen_string_literal: true

# Renders an executed contract's signed PDF and stores it as the contract's
# `signed_contract` ContractDocument. Runs in the background (never on the request
# thread) so signing/execution stays snappy even under a burst. Idempotent —
# skips if a signed PDF is already attached.
class GenerateContractPdfJob < ApplicationJob
  queue_as :default

  def perform(contract_id)
    contract = Contract.find_by(id: contract_id)
    return unless contract&.signing_executed?
    return if contract.signed_pdf_document.present?

    pdf = ContractPdf.new(contract).render
    doc = contract.contract_documents.where(document_type: "signed_contract").first_or_create!(name: "Signed Contract")
    doc.file.attach(
      io: StringIO.new(pdf),
      filename: "contract-#{contract.id}-signed.pdf",
      content_type: "application/pdf"
    )
  end
end
