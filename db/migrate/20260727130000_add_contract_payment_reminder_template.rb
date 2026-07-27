# frozen_string_literal: true

# A ContentTemplate the Money → Incoming section renders when an org nudges a
# payer about an outstanding incoming contract payment. Channel "both": it lands
# as an in-app message (if the payer has an account) and as an email carrying the
# pay link. All copy flows through ContentTemplateService — see the seeded
# template rather than hardcoding this anywhere.
class AddContractPaymentReminderTemplate < ActiveRecord::Migration[8.1]
  KEY = "contract_payment_reminder"

  BODY = <<~HTML
    <p>Hi {{payer_name}},</p>
    <p>This is a friendly reminder that <strong>{{amount}}</strong> is due to {{organization_name}} for {{description}} (due {{due_date}}).</p>
    {{#custom_message}}<p>{{custom_message}}</p>{{/custom_message}}
    <p><a href="{{pay_url}}" style="display:inline-block;padding:10px 20px;background-color:#ec4899;color:#ffffff;text-decoration:none;border-radius:6px;font-weight:600;">Pay now</a></p>
    <p>Or open this link to pay: {{pay_url}}</p>
    <p>Thank you!</p>
  HTML

  VARIABLES = [
    { "name" => "payer_name",        "description" => "Name of the person or company that owes the payment" },
    { "name" => "organization_name", "description" => "The organization collecting the payment" },
    { "name" => "amount",            "description" => "Formatted amount due (e.g. $250.00)" },
    { "name" => "description",       "description" => "What the payment is for" },
    { "name" => "due_date",          "description" => "Formatted due date" },
    { "name" => "pay_url",           "description" => "Link where the payer can settle the payment" },
    { "name" => "custom_message",    "description" => "Optional note from the organization (omitted when blank)" }
  ].freeze

  def up
    return if ContentTemplate.exists?(key: KEY)

    ContentTemplate.create!(
      key: KEY,
      name: "Contract Payment Reminder",
      subject: "Reminder: {{amount}} due to {{organization_name}}",
      body: BODY,
      category: "reminder",
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
