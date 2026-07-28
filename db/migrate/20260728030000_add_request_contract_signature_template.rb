# frozen_string_literal: true

# A ContentTemplate rendered when an org sends a contract out for e-signature.
# Channel "both": it lands as an in-app message (if the signer has an account) and
# as an email carrying the signing link. All copy flows through
# ContentTemplateService — edit the seeded template, never hardcode this.
class AddRequestContractSignatureTemplate < ActiveRecord::Migration[8.1]
  KEY = "request_contract_signature"

  BODY = <<~HTML
    <p>Hi {{recipient_name}},</p>
    <p>{{organization_name}} has prepared a contract for {{contract_name}} and would like you to review and sign it.</p>
    {{#custom_message}}<p>{{custom_message}}</p>{{/custom_message}}
    <p><a href="{{sign_url}}" style="display:inline-block;padding:10px 20px;background-color:#ec4899;color:#ffffff;text-decoration:none;border-radius:6px;font-weight:600;">Review &amp; sign</a></p>
    <p>Or open this link to review and sign: {{sign_url}}</p>
    <p>No account is needed — the link opens the contract for you to read and sign.</p>
    <p>Thank you!</p>
  HTML

  VARIABLES = [
    { "name" => "recipient_name",    "description" => "Name of the person/company being asked to sign" },
    { "name" => "organization_name", "description" => "The organization sending the contract" },
    { "name" => "contract_name",     "description" => "What the contract is for (production/show name)" },
    { "name" => "sign_url",          "description" => "No-login link where they review and sign" },
    { "name" => "custom_message",    "description" => "Optional note from the organization (omitted when blank)" }
  ].freeze

  def up
    return if ContentTemplate.exists?(key: KEY)

    ContentTemplate.create!(
      key: KEY,
      name: "Request Contract Signature",
      subject: "Please review & sign your contract with {{organization_name}}",
      body: BODY,
      category: "contract",
      channel: "both",
      template_type: "structured",
      active: true,
      available_variables: VARIABLES
    )
  end

  def down
    ContentTemplate.find_by(key: KEY)&.destroy
  end
end
