# frozen_string_literal: true

# The words of the notifications about a contractor's request on a contract
# date (ContractDateRequestNotices; Tim, 2026-11-16). Each is a seeded
# ContentTemplate (the SuperadminTemplates pattern) and a notification only:
# the Notifications list and a push, never an email. The subject is what the
# notification says; the body is kept for the template's editor and says the
# same.
class ContractDateRequestTemplates
  REQUEST_VARIABLES = [
    { "name" => "contractor_name", "description" => "The contractor on the contract" },
    { "name" => "organization_name", "description" => "The organization the contract is with" },
    { "name" => "production_name", "description" => "The production the contract is for" },
    { "name" => "note", "description" => "What they wrote, if anything" }
  ].freeze

  TEMPLATES = [
    { key: "contract_date_request_asked", name: "A contractor requests a date change (to the organization)",
      subject: "{{contractor_name}} {{requests_words}}",
      body: %(<p>{{contractor_name}} {{requests_words}}, on the contract for {{production_name}}.</p>{{#note}}<p>"{{note}}"</p>{{/note}}<p><a href="{{contract_url}}">Open the contract</a></p>),
      variables: REQUEST_VARIABLES + [
        { "name" => "requests_words", "description" => "The request, e.g. requests to move Fri Dec 18 to 7:30 PM" },
        { "name" => "contract_url", "description" => "The contract's page" } ] },
    { key: "contract_date_request_reminder", name: "A date request still waiting (to the organization)",
      subject: "{{contractor_name}} is still waiting on {{request_phrase}}",
      body: %(<p>{{contractor_name}} is still waiting on {{request_phrase}}, on the contract for {{production_name}}.</p><p><a href="{{contract_url}}">Open the contract</a></p>),
      variables: REQUEST_VARIABLES + [
        { "name" => "request_phrase", "description" => "The request, e.g. the request to move Fri Dec 18 to 7:30 PM" },
        { "name" => "contract_url", "description" => "The contract's page" } ] },
    { key: "contract_date_request_done", name: "A date request done (to the contractor)",
      subject: "{{organization_name}} {{outcome_words}}, as you requested",
      body: %(<p>{{organization_name}} {{outcome_words}}, as you requested.</p><p><a href="{{contracts_url}}">Open My Contracts</a></p>),
      variables: REQUEST_VARIABLES + [
        { "name" => "outcome_words", "description" => "What changed, e.g. moved Fri Dec 18 to 7:30 PM" },
        { "name" => "contracts_url", "description" => "My Contracts" } ] },
    { key: "contract_date_request_kept", name: "A date request answered no (to the contractor)",
      subject: "{{organization_name}} {{kept_words}}",
      body: %(<p>{{organization_name}} {{kept_words}}.</p>{{#note}}<p>"{{note}}"</p>{{/note}}<p><a href="{{contracts_url}}">Open My Contracts</a></p>),
      variables: REQUEST_VARIABLES + [
        { "name" => "kept_words", "description" => "The answer, e.g. kept Fri Dec 18 at 8:00 PM" },
        { "name" => "contracts_url", "description" => "My Contracts" } ] },
    { key: "contract_date_request_superseded", name: "A date request that no longer applies (to the contractor)",
      subject: "{{your_request}} no longer applies: {{reason}}",
      body: %(<p>{{your_request}} no longer applies: {{reason}}.</p><p><a href="{{contracts_url}}">Open My Contracts</a></p>),
      variables: REQUEST_VARIABLES + [
        { "name" => "your_request", "description" => "The request, e.g. Your request to move Fri Dec 18 to 7:30 PM" },
        { "name" => "reason", "description" => "What changed, e.g. that date is now Fri Dec 18, 9:00 PM" },
        { "name" => "contracts_url", "description" => "My Contracts" } ] }
  ].freeze

  def self.ensure!(keys: nil, overwrite: false)
    TEMPLATES.each do |spec|
      next if keys && !keys.include?(spec[:key])

      template = ContentTemplate.find_or_initialize_by(key: spec[:key])
      next if template.persisted? && !overwrite

      template.assign_attributes(name: spec[:name], category: "contracts", channel: "message", template_type: "structured",
                                 active: true, subject: spec[:subject], body: spec[:body], available_variables: spec[:variables])
      template.save!
    end
  end
end
