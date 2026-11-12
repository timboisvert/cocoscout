# frozen_string_literal: true

# The notification a manager gets once a bank statement they brought in has
# been matched to the books (Books V1.3, plan D3).
class AddBankStatementReadyTemplate < ActiveRecord::Migration[8.1]
  class Template < ActiveRecord::Base
    self.table_name = "content_templates"
  end

  def up
    t = Template.find_or_initialize_by(key: "bank_statement_ready")
    t.assign_attributes(
      name: "Bank statement ready",
      subject: "{{statement}} is in: {{matched}} matched the books, {{to_deal_with}} to deal with",
      body: "<p>Hi {{recipient_name}},</p>" \
            "<p>The bank statement you brought in for {{organization_name}} ({{statement}}, {{lines}} lines) has been checked " \
            "against the books: {{matched}} matched by themselves, {{suggested}} look like something on the books and need a yes, " \
            "and {{to_deal_with}} are left to record or ignore.</p>" \
            "<p><a href=\"{{bank_url}}\">Open Books → Bank</a>.</p>",
      category: "books",
      channel: "message",
      active: true,
      available_variables: %w[recipient_name organization_name statement lines matched suggested to_deal_with bank_url]
    )
    t.save!
  end

  def down
    Template.where(key: "bank_statement_ready").delete_all
  end
end
