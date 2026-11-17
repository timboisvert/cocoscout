# frozen_string_literal: true

# The words of the notifications about connecting a contract to the
# contractor's own organization (ContractConnectionNotices; Tim, 2026-11-17).
# Each is a seeded ContentTemplate and a notification only: the Notifications
# list and a push, never an email.
class ContractConnectionTemplates
  VARIABLES = [
    { "name" => "contractor_name", "description" => "The contractor on the contract" },
    { "name" => "organization_name", "description" => "The organization that wrote the contract" },
    { "name" => "linked_organization_name", "description" => "The contractor's own organization" },
    { "name" => "production_name", "description" => "The production the contract is for" },
    { "name" => "linked_production_name", "description" => "The production in the contractor's organization" },
    { "name" => "note", "description" => "What they wrote, if anything" }
  ].freeze

  TEMPLATES = [
    { key: "contract_connection_offer", name: "A contract can be connected to the contractor's own organization (to the contractor)",
      subject: "You can connect your {{organization_name}} contract to {{linked_organization_name}}",
      body: %(<p>{{organization_name}} has a contract with {{contractor_name}} for {{production_name}}, and you also run an organization of your own on CocoScout. If you connect the two, the contract's dates and their ticket sales appear in your own production, so you and your team can see them without typing anything in again.</p><p><a href="{{connect_url}}">See what connecting does</a></p>) },
    { key: "contract_connection_told", name: "The organization points out that the contract can be connected (to the contractor)",
      subject: "{{organization_name}} would like you to know you can see these dates in an organization of your own",
      body: %(<p>{{organization_name}} would like you to know that the dates on your contract for {{production_name}}, and how their tickets are selling, can appear in an organization of your own on CocoScout, where you and your team can see them alongside the rest of your show.</p><p><a href="{{connect_url}}">See how it works</a></p>) },
    { key: "contract_connection_pay_to_balance", name: "Contract payments will go into the contractor's organization's balance (to the organization)",
      subject: "Your payments to {{contractor_name}} for {{production_name}} will go into {{linked_organization_name}}'s CocoScout balance",
      body: %(<p>{{contractor_name}} chose to have what you pay under the contract for {{production_name}} sent into {{linked_organization_name}}'s CocoScout balance, in place of a bank. Each payment still goes on your payout run as one line, and comes out of your balance like any other. Payments already on a run go where they were going.</p><p><a href="{{contract_url}}">Open the contract</a></p>) },
    { key: "contract_connection_pay_to_bank", name: "Contract payments go back to the contractor's bank (to the organization)",
      subject: "Your payments to {{contractor_name}} for {{production_name}} will go to {{contractor_name}}'s bank again",
      body: %(<p>{{contractor_name}} chose to have what you pay under the contract for {{production_name}} sent to a bank again, and no longer into {{linked_organization_name}}'s CocoScout balance. Payments already on a run go where they were going.</p><p><a href="{{contract_url}}">Open the contract</a></p>) },
    { key: "contract_share_paid_into_balance", name: "A contract payment arrived in the balance (to the contractor's organization)",
      subject: "{{organization_name}} paid {{amount}} into {{linked_organization_name}}'s balance",
      body: %(<p>{{organization_name}} paid {{amount}} into {{linked_organization_name}}'s CocoScout balance, for your contract with them. It is there now: you can pay people from it or withdraw it.</p><p><a href="{{connections_url}}">Open Connections</a></p>) },
    { key: "contract_connection_requested", name: "A contractor requests to connect their organization (to the organization)",
      subject: "{{contractor_name}} requests to connect {{linked_organization_name}} to the contract for {{production_name}}",
      body: %(<p>{{contractor_name}} requests to connect {{linked_organization_name}} to the contract for {{production_name}}. It needs your OK.</p>{{#note}}<p>"{{note}}"</p>{{/note}}<p><a href="{{contract_url}}">Open the contract</a></p>) },
    { key: "contract_connection_reminder", name: "A connection request still waiting (to the organization)",
      subject: "{{contractor_name}} is still waiting on the connection for {{production_name}}",
      body: %(<p>{{contractor_name}} is still waiting on the connection for {{production_name}}.</p><p><a href="{{contract_url}}">Open the contract</a></p>) },
    { key: "contract_connection_connected_by_earlier_yes", name: "A later contract connected under an earlier yes (to the organization)",
      subject: "{{contractor_name}} connected the contract for {{production_name}} to {{linked_organization_name}}",
      body: %(<p>{{contractor_name}} connected the contract for {{production_name}} to {{linked_organization_name}}. You weren't asked this time, because {{organization_name}} chose to connect later contracts with {{contractor_name}}. You can change that choice, or unlink this contract, on the contract's page.</p><p><a href="{{contract_url}}">Open the contract</a></p>) },
    { key: "contract_connection_accepted", name: "A connection accepted (to the contractor)",
      subject: "{{organization_name}} connected your contract. Their dates are in {{linked_production_name}}.",
      body: %(<p>{{organization_name}} connected your contract for {{production_name}}. Their dates are in {{linked_production_name}}, in {{linked_organization_name}}.</p><p><a href="{{contracts_url}}">Open My Contracts</a></p>) },
    { key: "contract_connection_declined", name: "A connection declined (to the contractor)",
      subject: "{{organization_name}} didn't connect your contract for {{production_name}}",
      body: %(<p>{{organization_name}} didn't connect your contract for {{production_name}}.</p>{{#note}}<p>"{{note}}"</p>{{/note}}<p><a href="{{contracts_url}}">Open My Contracts</a></p>) },
    { key: "contract_connection_unlinked_by_contractor", name: "A connection ended by the contractor's organization (to the organization)",
      subject: "{{linked_organization_name}} unlinked the contract for {{production_name}}",
      body: %(<p>{{linked_organization_name}} unlinked the contract for {{production_name}}. The contract itself hasn't changed.</p><p><a href="{{contract_url}}">Open the contract</a></p>) },
    { key: "contract_connection_unlinked_by_organization", name: "A connection ended by the organization (to the contractor)",
      subject: "{{organization_name}} unlinked your contract for {{production_name}}",
      body: %(<p>{{organization_name}} unlinked your contract for {{production_name}}. The contract itself hasn't changed, and the dates already in {{linked_production_name}} stay, as your own.</p><p><a href="{{contracts_url}}">Open My Contracts</a></p>) }
  ].freeze

  def self.ensure!(keys: nil, overwrite: false)
    TEMPLATES.each do |spec|
      next if keys && !keys.include?(spec[:key])

      template = ContentTemplate.find_or_initialize_by(key: spec[:key])
      next if template.persisted? && !overwrite

      template.assign_attributes(name: spec[:name], category: "contracts", channel: "message", template_type: "structured",
                                 active: true, subject: spec[:subject], body: spec[:body], available_variables: VARIABLES)
      template.save!
    end
  end
end
