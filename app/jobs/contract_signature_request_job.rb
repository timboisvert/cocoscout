# frozen_string_literal: true

# Notifies a contract's counterparty that there's a contract waiting for them to
# sign, over both channels (in-app message + email) via ContentTemplateService.
# Runs in the background so hitting "Send" never blocks the request on mail/message
# delivery. If the counterparty has no reachable Person/email, it no-ops — the
# producer can still share the signing link by hand.
class ContractSignatureRequestJob < ApplicationJob
  queue_as :default

  def perform(contract_id, sign_url, sender_id = nil)
    contract = Contract.find_by(id: contract_id)
    return unless contract&.signing_out_for_signature?

    contractor = contract.contractor
    person = contractor&.ensure_person!
    return if person.nil?

    ContentTemplateService.deliver(
      template_key: "request_contract_signature",
      variables: {
        recipient_name: contractor.name.presence || person.name,
        organization_name: contract.organization.name,
        contract_name: contract.production_name.presence || contract.production&.name || "your contract",
        sign_url: sign_url,
        custom_message: ""
      },
      sender: (User.find_by(id: sender_id) if sender_id),
      recipients: [ person ],
      organization: contract.organization,
      production: contract.production,
      mailer_class: Manage::ContractSignatureMailer,
      mailer_method: :signature_request
    )
  end
end
