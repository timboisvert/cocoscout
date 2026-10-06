# frozen_string_literal: true

# The words of the emails an organization sends about an invoice for contract
# money: the invoice itself, a reminder, and the receipt once it's paid. Each
# is a seeded ContentTemplate (the PlatformTemplates pattern). The invoice and
# the reminder only ever go when a manager presses Send; the receipt goes on
# its own when the payment is paid.
class ContractInvoiceTemplates
  VARIABLES = [
    { "name" => "payer_name", "description" => "Who owes the money" },
    { "name" => "organization_name", "description" => "The organization" },
    { "name" => "invoice_number", "description" => "e.g. SG-0012" },
    { "name" => "amount", "description" => "The amount, e.g. $350.00" },
    { "name" => "description", "description" => "What the payment is for" },
    { "name" => "invoice_url", "description" => "The invoice page, where they can pay" },
    { "name" => "invoice_pdf_url", "description" => "The invoice as a PDF" }
  ].freeze
  DUE = [ { "name" => "due_date", "description" => "When it's due" },
          { "name" => "custom_message", "description" => "The manager's note, if they wrote one" },
          { "name" => "other_payment_methods", "description" => "Other ways the contract lets them pay, e.g. check or cash" } ].freeze

  TEMPLATES = [
    { key: "contract_invoice", name: "Contract invoice", channel: "both",
      subject: "Invoice {{invoice_number}} from {{organization_name}}: {{amount}} due {{due_date}}",
      body: %(<p>Hi {{payer_name}},</p><p>Here's invoice {{invoice_number}} from {{organization_name}} for {{description}}: <strong>{{amount}}</strong>, due {{due_date}}.</p>{{#custom_message}}<p>{{custom_message}}</p>{{/custom_message}}<p><a href="{{invoice_url}}">View and pay the invoice</a> · <a href="{{invoice_pdf_url}}">Download it as a PDF</a></p>{{#other_payment_methods}}<p>You can also pay by {{other_payment_methods}}. Reply to arrange it.</p>{{/other_payment_methods}}),
      variables: VARIABLES + DUE },
    { key: "contract_invoice_reminder", name: "Contract invoice reminder", channel: "both",
      subject: "Reminder: invoice {{invoice_number}} from {{organization_name}}, {{amount}} due {{due_date}}",
      body: %(<p>Hi {{payer_name}},</p><p>A reminder that invoice {{invoice_number}} from {{organization_name}} for {{description}} is still open: <strong>{{amount}}</strong>, due {{due_date}}.</p>{{#custom_message}}<p>{{custom_message}}</p>{{/custom_message}}<p><a href="{{invoice_url}}">View and pay the invoice</a> · <a href="{{invoice_pdf_url}}">Download it as a PDF</a></p>{{#other_payment_methods}}<p>You can also pay by {{other_payment_methods}}. Reply to arrange it.</p>{{/other_payment_methods}}),
      variables: VARIABLES + DUE },
    { key: "contract_payment_receipt", name: "Contract payment receipt", channel: "both",
      subject: "Receipt from {{organization_name}}: {{amount}} paid",
      body: %(<p>Hi {{payer_name}},</p><p>{{organization_name}} received your payment of <strong>{{amount}}</strong> for {{description}} on {{paid_on}}{{#paid_via}} ({{paid_via}}){{/paid_via}}. Thank you.</p><p>Invoice {{invoice_number}} is marked paid: <a href="{{invoice_url}}">view it</a> or <a href="{{invoice_pdf_url}}">download the receipt as a PDF</a>.</p>),
      variables: VARIABLES + [ { "name" => "paid_on", "description" => "The day it was paid" },
                               { "name" => "paid_via", "description" => "How, e.g. by check (blank when paid online)" } ] }
  ].freeze

  def self.ensure!(keys: nil, overwrite: false)
    TEMPLATES.each do |spec|
      next if keys && !keys.include?(spec[:key])

      template = ContentTemplate.find_or_initialize_by(key: spec[:key])
      next if template.persisted? && !overwrite

      template.assign_attributes(name: spec[:name], category: "payments", channel: spec[:channel], template_type: "structured",
                                 active: true, subject: spec[:subject], body: spec[:body], available_variables: spec[:variables])
      template.save!
    end
  end
end
