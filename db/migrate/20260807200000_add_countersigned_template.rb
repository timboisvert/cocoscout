# frozen_string_literal: true

# The receipt: once both parties have signed, the counterparty gets their copy.
# Email carries the countersigned PDF as an attachment — most counterparties
# have no CocoScout account, so the email is the copy they actually keep — and
# the in-app message points anyone who does have one at their contracts page.
class AddCountersignedTemplate < ActiveRecord::Migration[8.1]
  class Template < ActiveRecord::Base
    self.table_name = "content_templates"
  end

  def up
    t = Template.find_or_initialize_by(key: "contract_countersigned_to_signer")
    t.assign_attributes(
      name: "Contract Fully Signed (counterparty copy)",
      subject: "Signed: your {{organization_name}} contract for {{production_name}}",
      body: "<p>Hi {{recipient_name}},</p>" \
            "<p>Your contract with {{organization_name}} for {{production_name}} is now signed by " \
            "both of you, as of {{signed_on}}. Nothing further is needed from you.</p>" \
            "<p>A copy signed by both parties is attached to this email. You can also download it " \
            "any time from <a href=\"{{contracts_url}}\">your contracts</a>.</p>",
      category: "contracts",
      channel: "both",
      active: true,
      available_variables: %w[recipient_name organization_name production_name signed_on version_label contracts_url]
    )
    t.save!
  end

  def down
    Template.where(key: "contract_countersigned_to_signer").delete_all
  end
end
