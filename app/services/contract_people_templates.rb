# frozen_string_literal: true

# The words of the email that invites someone onto a contract (a contract
# person, docs/contract_people_plan.md), a seeded ContentTemplate (the
# PlatformTemplates pattern). It goes when a contract is activated with
# someone staged by email, or when a manager adds them to a live contract.
class ContractPeopleTemplates
  TEMPLATES = [
    { key: "contract_person_invitation", name: "Invitation onto a contract", channel: "email",
      subject: "{{contractor_name}}'s contract with {{organization_name}}, on CocoScout",
      body: %(<p>Hi{{#name}} {{name}}{{/name}},</p><p>{{contractor_name}} has a contract with {{organization_name}} for {{production_name}}, and you're on it. Make a free CocoScout account and you'll see the dates, how tickets are selling, who's coming, and what the contract pays.</p><p><a href="{{accept_url}}">Accept the invitation</a></p>),
      variables: [ { "name" => "name", "description" => "Their name, when the manager gave one" },
                   { "name" => "contractor_name", "description" => "The contractor the contract is with" },
                   { "name" => "organization_name", "description" => "The organization" },
                   { "name" => "production_name", "description" => "The production under contract" },
                   { "name" => "accept_url", "description" => "Where they accept and make their account" } ] }
  ].freeze

  def self.ensure!(keys: nil, overwrite: false)
    TEMPLATES.each do |spec|
      next if keys && !keys.include?(spec[:key])

      template = ContentTemplate.find_or_initialize_by(key: spec[:key])
      next if template.persisted? && !overwrite

      template.assign_attributes(name: spec[:name], category: "contracts", channel: spec[:channel], template_type: "structured",
                                 active: true, subject: spec[:subject], body: spec[:body], available_variables: spec[:variables])
      template.save!
    end
  end
end
