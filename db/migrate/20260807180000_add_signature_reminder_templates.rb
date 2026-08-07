# frozen_string_literal: true

# Copy for chasing an unsigned contract and for telling both sides when one
# expires. Migration-owned so it ships with the deploy — the reminder job runs
# daily and a missing template would raise inside it.
class AddSignatureReminderTemplates < ActiveRecord::Migration[8.1]
  class Template < ActiveRecord::Base
    self.table_name = "content_templates"
  end

  TEMPLATES = [
    {
      key: "contract_signature_nudge",
      name: "Contract Signature Reminder (counterparty)",
      subject: "Reminder: your {{organization_name}} contract is waiting for your signature",
      body: "<p>Hi {{recipient_name}},</p>" \
            "<p>Your contract with {{organization_name}} for {{production_name}} is still waiting " \
            "for your signature. It needs to be signed by <strong>{{deadline}}</strong>, after which " \
            "it expires and {{organization_name}} will have to send it again.</p>" \
            "{{#urgency}}<p><strong>{{urgency}}</strong></p>{{/urgency}}" \
            "<p><a href=\"{{sign_url}}\">Read and sign the contract</a></p>",
      available_variables: %w[recipient_name organization_name production_name deadline days_left urgency sign_url],
      channel: "both"
    },
    {
      key: "contract_signature_expired",
      name: "Contract Signature Expired (counterparty)",
      subject: "Your {{organization_name}} contract has expired",
      body: "<p>Hi {{recipient_name}},</p>" \
            "<p>The contract with {{organization_name}} for {{production_name}} wasn't signed in time, " \
            "so the link has expired and it's no longer valid to sign.</p>" \
            "<p>If you still want to go ahead, get in touch with {{organization_name}} and they'll " \
            "send you a fresh copy.</p>",
      available_variables: %w[recipient_name organization_name production_name],
      channel: "both"
    },
    {
      key: "contract_signature_unsigned_manager",
      name: "Contract Unsigned (manager alert)",
      subject: "{{contractor_name}}'s contract {{state}}",
      body: "<p>The contract with {{contractor_name}} for {{production_name}} {{state}}." \
            "{{#deadline}} The deadline was {{deadline}}.{{/deadline}}</p>" \
            "<p>Their signature link is no longer live, and the contract is back to ready-to-send — " \
            "your signature and the document are exactly as you left them, so re-sending is one click.</p>" \
            "<p><a href=\"{{contract_url}}\">Open the contract</a></p>",
      available_variables: %w[contractor_name production_name organization_name state deadline contract_url],
      channel: "message"
    }
  ].freeze

  def up
    TEMPLATES.each do |attrs|
      t = Template.find_or_initialize_by(key: attrs[:key])
      t.assign_attributes(name: attrs[:name], subject: attrs[:subject], body: attrs[:body],
                          category: "contracts", channel: attrs[:channel], active: true,
                          available_variables: attrs[:available_variables])
      t.save!
    end
  end

  def down
    Template.where(key: TEMPLATES.map { |t| t[:key] }).delete_all
  end
end
