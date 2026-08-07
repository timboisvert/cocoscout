# frozen_string_literal: true

# Renders an executed contract VERSION's signed PDF and stores it as a
# `signed_contract` ContractDocument belonging to that version. Runs in the
# background so signing stays snappy.
#
# Keyed per version, which is the fix for "never regenerates after an
# amendment": the old job returned early forever once any signed PDF existed,
# so an amended contract kept serving the document from before the change.
class GenerateContractPdfJob < ApplicationJob
  queue_as :default

  # The version argument is optional so jobs enqueued before this shipped still
  # resolve — they fall back to the latest executed version, which is right.
  def perform(contract_id, contract_version_id = nil)
    contract = Contract.find_by(id: contract_id)
    return unless contract

    version = if contract_version_id
                contract.contract_versions.find_by(id: contract_version_id)
    else
                contract.latest_executed_version
    end
    return unless version&.executed_at
    return if version.pdf_document.present?

    pdf = ContractPdf.new(version).render
    doc = contract.contract_documents
                  .where(document_type: "signed_contract", contract_version_id: version.id)
                  .first_or_create!(name: "Signed Contract #{version.label}")
    doc.file.attach(
      io: StringIO.new(pdf),
      filename: "contract-#{contract.id}-#{version.label}-signed.pdf",
      content_type: "application/pdf"
    )
  end
end
