# frozen_string_literal: true

# Notifies the organization's chosen managers, via in-app message only, that a
# contract's counterparty has signed. Runs in the background off the signing
# request. No-ops when the org selected no recipients (or has none). Attributed as
# an automated notification (message_type: :system), never as a sending user.
class ContractSignedNotificationJob < ApplicationJob
  queue_as :default

  def perform(contract_id)
    contract = Contract.find_by(id: contract_id)
    return unless contract&.signing_executed?

    recipients = contract.organization.contract_notification_recipients
    return if recipients.empty?

    ContentTemplateService.deliver(
      template_key: "contract_signed_manager",
      variables: {
        contractor_name: contract.contractor_name,
        production_name: contract.production_name.presence || contract.production&.name || "a contract",
        organization_name: contract.organization.name,
        contract_url: Rails.application.routes.url_helpers.manage_contract_path(contract)
      },
      sender: nil,
      recipients: recipients,
      organization: contract.organization,
      production: contract.production,
      message_type: :system
    )
  end
end
