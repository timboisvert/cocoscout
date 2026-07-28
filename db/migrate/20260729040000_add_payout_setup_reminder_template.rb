# frozen_string_literal: true

# ContentTemplate for the "you have money waiting — connect a bank" reminder sent
# from a show's payout page to people who are owed but haven't set up payment.
# In-app message channel (no email). All copy flows through ContentTemplateService.
class AddPayoutSetupReminderTemplate < ActiveRecord::Migration[8.1]
  KEY = "payout_setup_reminder"

  BODY = <<~HTML
    <p>Hi {{recipient_name}},</p>
    <p>You have <strong>{{amount}}</strong> from {{organization_name}} ready to be paid out. To receive it, just add your payment details — we'll deposit it straight to your bank once you're set up.</p>
    <p><a href="{{setup_link}}">Set up your payment details</a></p>
  HTML

  VARIABLES = [
    { "name" => "recipient_name",    "description" => "The payee's first name" },
    { "name" => "organization_name", "description" => "The organization that owes them" },
    { "name" => "amount",            "description" => "Amount they're owed, formatted (e.g. $150.00)" },
    { "name" => "setup_link",        "description" => "Link to set up payment details / connect a bank" }
  ].freeze

  def up
    return if ContentTemplate.exists?(key: KEY)

    ContentTemplate.create!(
      key: KEY,
      name: "Payout Setup Reminder",
      subject: "You have {{amount}} ready to be paid by {{organization_name}}",
      body: BODY,
      category: "payments",
      channel: "message",
      template_type: "structured",
      active: true,
      available_variables: VARIABLES
    )
  end

  def down
    ContentTemplate.find_by(key: KEY)&.destroy
  end
end
