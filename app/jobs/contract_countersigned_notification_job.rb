# frozen_string_literal: true

# Tells the counterparty their contract is fully signed, and gives them the
# copy they keep.
#
# Two channels on purpose: the email carries the countersigned PDF as an
# attachment, because that's the document they'll want in their own records
# and most of them have no CocoScout account to come back to. The in-app
# message links to their contracts page, where the same PDF is downloadable.
#
# Runs after the PDF exists — GenerateContractPdfJob enqueues it — so the
# attachment is never missing.
class ContractCountersignedNotificationJob < ApplicationJob
  queue_as :default

  def perform(contract_id, contract_version_id = nil)
    contract = Contract.find_by(id: contract_id)
    return unless contract

    version = contract_version_id ? contract.contract_versions.find_by(id: contract_version_id) : contract.latest_executed_version
    return unless version&.executed_at

    person = contract.signer_person_record
    return unless person

    rendered = ContentTemplateService.render("contract_countersigned_to_signer", variables(contract, version, person))

    email_pdf(person, contract, version, rendered)
    # Silently no-ops for a counterparty without an account, which is the
    # common case — the email above is what actually reaches them.
    MessageService.send_direct(
      sender: nil,
      recipient_person: person,
      subject: rendered[:subject],
      body: rendered[:body],
      organization: contract.organization,
      system_generated: true,
      skip_digest: true
    )
  end

  private

  def variables(contract, version, person)
    {
      recipient_name: person.name,
      organization_name: contract.organization.name,
      production_name: contract.production_name.presence || contract.contractor_name,
      signed_on: version.executed_at.strftime("%B %-d, %Y"),
      version_label: version.label,
      contracts_url: Rails.application.routes.url_helpers.my_contracts_url(**url_options)
    }
  end

  def email_pdf(person, contract, version, rendered)
    document = version.pdf_document
    data = document&.file&.attached? ? document.file.download : nil

    Manage::ContractSignedMailer.countersigned(
      person, rendered[:subject], rendered[:body], data,
      "#{contract.contractor_name.parameterize}-contract-#{version.label}.pdf"
    ).deliver_now
  rescue StandardError => e
    Rails.logger.error("[ContractCountersignedNotificationJob] email #{contract.id}: #{e.class}: #{e.message}")
  end

  def url_options
    Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
  end
end
