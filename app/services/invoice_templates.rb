# frozen_string_literal: true

# The words of the emails an organization sends about an invoice: the
# invoice itself, a reminder, and the receipt once it's paid, for each kind
# of invoice (Invoice). Each is a seeded ContentTemplate (the
# PlatformTemplates pattern). The invoice goes when a manager presses Send;
# a reminder when they press it again, or by itself on the days the invoice
# was set to (InvoiceRemindersJob); the receipt on its own when it's paid.
#
# An invoice to anyone is an email. A contract payment's also reaches a
# payer with a CocoScout account as a message, and says the other ways the
# contract lets them pay.
class InvoiceTemplates
  VARIABLES = [
    { "name" => "payer_name", "description" => "Who the invoice is to" },
    { "name" => "organization_name", "description" => "The organization" },
    { "name" => "invoice_number", "description" => "e.g. SG-0014" },
    { "name" => "amount", "description" => "What is owed (on a receipt, the invoice's total), e.g. $1,200.00" },
    { "name" => "description", "description" => "What it is for" },
    { "name" => "invoice_url", "description" => "The invoice page, where they can pay" },
    { "name" => "invoice_pdf_url", "description" => "The invoice as a PDF" }
  ].freeze
  DUE = [ { "name" => "due_date", "description" => "When it is due" } ].freeze
  PAID = [ { "name" => "paid_on", "description" => "The day it was paid" },
           { "name" => "paid_via", "description" => "How, e.g. by check (blank when paid online)" } ].freeze
  OWN = DUE + [ { "name" => "custom_message", "description" => "The message on the invoice, if there is one" },
                { "name" => "ways_to_pay", "description" => "How they can pay, e.g. card, bank transfer and check" } ].freeze
  CONTRACT = DUE + [ { "name" => "custom_message", "description" => "The manager's note, if they wrote one" },
                     { "name" => "other_payment_methods", "description" => "Other ways the contract lets them pay, e.g. check or cash" } ].freeze

  INVOICE_SUBJECT = "Invoice {{invoice_number}} from {{organization_name}}: {{amount}} due {{due_date}}"
  REMINDER_SUBJECT = "Reminder: invoice {{invoice_number}} from {{organization_name}}, {{amount}} due {{due_date}}"
  RECEIPT_SUBJECT = "Receipt from {{organization_name}}: {{amount}} paid"
  LINKS = %(<p><a href="{{invoice_url}}">View and pay the invoice</a> · <a href="{{invoice_pdf_url}}">Download it as a PDF</a></p>)
  NOTE = "{{#custom_message}}<p>{{custom_message}}</p>{{/custom_message}}"
  RECEIPT_BODY = %(<p>Hi {{payer_name}},</p><p>{{organization_name}} received your payment of <strong>{{amount}}</strong> for {{description}} on {{paid_on}}{{#paid_via}} ({{paid_via}}){{/paid_via}}. Thank you.</p><p>Invoice {{invoice_number}} is marked paid: <a href="{{invoice_url}}">view it</a> or <a href="{{invoice_pdf_url}}">download the receipt as a PDF</a>.</p>)
  OWN_WAYS = "<p>You can pay by {{ways_to_pay}}.</p>"
  CONTRACT_WAYS = "{{#other_payment_methods}}<p>You can also pay by {{other_payment_methods}}. Reply to arrange it.</p>{{/other_payment_methods}}"

  TEMPLATES = [
    { key: "invoice", name: "Invoice", channel: "email", subject: INVOICE_SUBJECT,
      body: %(<p>Hi {{payer_name}},</p><p>Here is invoice {{invoice_number}} from {{organization_name}} for {{description}}: <strong>{{amount}}</strong>, due {{due_date}}.</p>#{NOTE}#{LINKS}#{OWN_WAYS}),
      variables: VARIABLES + OWN },
    { key: "invoice_reminder", name: "Invoice reminder", channel: "email", subject: REMINDER_SUBJECT,
      body: %(<p>Hi {{payer_name}},</p><p>A reminder that invoice {{invoice_number}} from {{organization_name}} for {{description}} is still open: <strong>{{amount}}</strong>, due {{due_date}}.</p>#{NOTE}#{LINKS}#{OWN_WAYS}),
      variables: VARIABLES + OWN },
    { key: "invoice_receipt", name: "Invoice receipt", channel: "email", subject: RECEIPT_SUBJECT, body: RECEIPT_BODY, variables: VARIABLES + PAID },
    { key: "contract_invoice", name: "Contract invoice", channel: "both", subject: INVOICE_SUBJECT,
      body: %(<p>Hi {{payer_name}},</p><p>Here's invoice {{invoice_number}} from {{organization_name}} for {{description}}: <strong>{{amount}}</strong>, due {{due_date}}.</p>#{NOTE}#{LINKS}#{CONTRACT_WAYS}),
      variables: VARIABLES + CONTRACT },
    { key: "contract_invoice_reminder", name: "Contract invoice reminder", channel: "both", subject: REMINDER_SUBJECT,
      body: %(<p>Hi {{payer_name}},</p><p>A reminder that invoice {{invoice_number}} from {{organization_name}} for {{description}} is still open: <strong>{{amount}}</strong>, due {{due_date}}.</p>#{NOTE}#{LINKS}#{CONTRACT_WAYS}),
      variables: VARIABLES + CONTRACT },
    { key: "contract_payment_receipt", name: "Contract payment receipt", channel: "both", subject: RECEIPT_SUBJECT, body: RECEIPT_BODY, variables: VARIABLES + PAID }
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
