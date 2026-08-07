# frozen_string_literal: true

# One manager template served both "still unsigned" and "expired", so the
# mid-way alert told the producer the link was dead and the contract was back
# with them — none of which was true yet. Two templates, each true.
#
# Also gives the final nudge its own subject: the escalation was in the body
# only, so the last reminder arrived looking identical to the first.
class SplitSignatureManagerAlerts < ActiveRecord::Migration[8.1]
  class Template < ActiveRecord::Base
    self.table_name = "content_templates"
  end

  TEMPLATES = [
    {
      key: "contract_signature_stalled_manager",
      name: "Contract Still Unsigned (manager alert)",
      subject: "{{contractor_name}} hasn't signed yet",
      body: "<p>The contract with {{contractor_name}} for {{production_name}} still hasn't been signed. " \
            "They have until <strong>{{deadline}}</strong>.</p>" \
            "<p>We've reminded them; this might be the point to pick up the phone. If it expires, " \
            "the contract comes back to you ready to send again.</p>" \
            "<p><a href=\"{{contract_url}}\">Open the contract</a></p>",
      available_variables: %w[contractor_name production_name organization_name deadline contract_url]
    },
    {
      key: "contract_signature_expired_manager",
      name: "Contract Signature Expired (manager alert)",
      subject: "{{contractor_name}}'s contract expired without being signed",
      body: "<p>The contract with {{contractor_name}} for {{production_name}} expired on " \
            "<strong>{{deadline}}</strong> without being signed.</p>" \
            "<p>Their link is no longer live and the contract is back to ready-to-send — your signature " \
            "and the document are exactly as you left them, so re-sending is one click.</p>" \
            "<p><a href=\"{{contract_url}}\">Open the contract</a></p>",
      available_variables: %w[contractor_name production_name organization_name deadline contract_url]
    }
  ].freeze

  def up
    TEMPLATES.each do |attrs|
      t = Template.find_or_initialize_by(key: attrs[:key])
      t.assign_attributes(name: attrs[:name], subject: attrs[:subject], body: attrs[:body],
                          category: "contracts", channel: "message", active: true,
                          available_variables: attrs[:available_variables])
      t.save!
    end
    Template.where(key: "contract_signature_unsigned_manager").delete_all
  end

  def down
    Template.where(key: TEMPLATES.map { |t| t[:key] }).delete_all
  end
end
