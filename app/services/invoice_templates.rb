# frozen_string_literal: true

# The words of the emails an organization sends about an invoice to anyone
# (plan D2): the invoice, a reminder, and the receipt once it's paid. Each
# is a seeded ContentTemplate, the same pattern as ContractInvoiceTemplates.
class InvoiceTemplates
  VARIABLES = [
    { "name" => "payer_name", "description" => "Who the invoice is to" },
    { "name" => "organization_name", "description" => "The organization" },
    { "name" => "invoice_number", "description" => "e.g. SG-0014" },
    { "name" => "amount", "description" => "The amount, e.g. $1,200.00" },
    { "name" => "description", "description" => "What it is for, the first line" },
    { "name" => "invoice_url", "description" => "The invoice page, where they can pay" },
    { "name" => "invoice_pdf_url", "description" => "The invoice as a PDF" },
    { "name" => "due_date", "description" => "When it is due" },
    { "name" => "custom_message", "description" => "The message on the invoice, if there is one" },
    { "name" => "ways_to_pay", "description" => "How they can pay, e.g. card, bank transfer and check" }
  ].freeze

  TEMPLATES = [
    { key: "invoice", name: "Invoice", channel: "email",
      subject: "Invoice {{invoice_number}} from {{organization_name}}: {{amount}} due {{due_date}}",
      body: %(<p>Hi {{payer_name}},</p><p>Here is invoice {{invoice_number}} from {{organization_name}} for {{description}}: <strong>{{amount}}</strong>, due {{due_date}}.</p>{{#custom_message}}<p>{{custom_message}}</p>{{/custom_message}}<p><a href="{{invoice_url}}">View and pay the invoice</a> · <a href="{{invoice_pdf_url}}">Download it as a PDF</a></p><p>You can pay by {{ways_to_pay}}.</p>),
      variables: VARIABLES },
    { key: "invoice_reminder", name: "Invoice reminder", channel: "email",
      subject: "Reminder: invoice {{invoice_number}} from {{organization_name}}, {{amount}} due {{due_date}}",
      body: %(<p>Hi {{payer_name}},</p><p>A reminder that invoice {{invoice_number}} from {{organization_name}} for {{description}} is still open: <strong>{{amount}}</strong>, due {{due_date}}.</p>{{#custom_message}}<p>{{custom_message}}</p>{{/custom_message}}<p><a href="{{invoice_url}}">View and pay the invoice</a> · <a href="{{invoice_pdf_url}}">Download it as a PDF</a></p><p>You can pay by {{ways_to_pay}}.</p>),
      variables: VARIABLES },
    { key: "invoice_receipt", name: "Invoice receipt", channel: "email",
      subject: "Receipt from {{organization_name}}: {{amount}} paid",
      body: %(<p>Hi {{payer_name}},</p><p>{{organization_name}} received your payment of <strong>{{amount}}</strong> for {{description}} on {{paid_on}}{{#paid_via}} ({{paid_via}}){{/paid_via}}. Thank you.</p><p>Invoice {{invoice_number}} is marked paid: <a href="{{invoice_url}}">view it</a> or <a href="{{invoice_pdf_url}}">download the receipt as a PDF</a>.</p>),
      variables: VARIABLES + [ { "name" => "paid_on", "description" => "The day it was paid" }, { "name" => "paid_via", "description" => "How, e.g. by check" } ] }
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
