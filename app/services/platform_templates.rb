# frozen_string_literal: true

# The words of the emails CocoScout sends about its own money, and the bank
# setup link a payee is sent, in one place (as TicketingTemplates and
# CourseTemplates are for theirs). Each is a seeded ContentTemplate.
class PlatformTemplates
  TEMPLATES = [
    { key: "payee_bank_setup_link", name: "Bank setup link for a payee", channel: "email",
      subject: "{{organization_name}} wants to pay you through CocoScout",
      body: %(<p>Hi {{first_name}},</p><p>{{organization_name}} pays people through CocoScout, straight to their bank. Connect yours here. It takes a few minutes, and you don't need a CocoScout account.</p><p><a href="{{setup_url}}">Connect your bank</a></p><p>This link is just for you, so please don't forward it. It works for 30 days. If you weren't expecting it, you can ignore this email.</p>),
      variables: [ { "name" => "first_name", "description" => "The payee's first name" },
                   { "name" => "organization_name", "description" => "The organization paying them" },
                   { "name" => "setup_url", "description" => "Their own bank setup link (no sign-in; 30 days)" } ] },
    { key: "account_deletion_requested", name: "Someone asked to delete their account", channel: "email",
      subject: "{{name}} asked to delete their CocoScout account",
      body: %(<p>{{name}} ({{email}}) asked to delete their CocoScout account from {{where}} on {{requested_on}}. They were told it would be done within 30 days, and can take it back from Account Settings until then.</p><p>Keep the payout and tax records the law needs; delete the rest from their Superadmin page.</p><p><a href="{{person_url}}">Open them in Superadmin</a></p>),
      variables: [ { "name" => "name", "description" => "Their name" },
                   { "name" => "email", "description" => "Their sign-in email" },
                   { "name" => "where", "description" => "The website or the iPhone app" },
                   { "name" => "requested_on", "description" => "The date they asked" },
                   { "name" => "person_url", "description" => "Their Superadmin page" } ] },
    { key: "cocoscout_money_check", name: "CocoScout money check needs a look", channel: "email",
      subject: "CocoScout's money check: {{headline}}",
      body: %(<p>This morning's check of CocoScout's Stripe balance against its records needs a look.</p>{{findings}}<p><a href="{{check_url}}">Open the Stripe check</a></p>),
      variables: [ { "name" => "headline", "description" => "One line: what's off" },
                   { "name" => "findings", "description" => "A list of what the check found" },
                   { "name" => "check_url", "description" => "The superadmin Stripe check page" } ] },
    { key: "org_monthly_statement", name: "Monthly CocoScout statement", channel: "email",
      subject: "Your CocoScout statement for {{month}}",
      body: %(<p>Hi {{first_name}},</p><p>Here's {{organization_name}}'s CocoScout statement for {{month}}. You paid CocoScout {{total_paid}}, and your CocoScout balance went from {{opening}} to {{closing}}. The statement is attached, and every statement is on your <a href="{{billing_url}}">Billing &amp; Plan page</a>.</p>),
      variables: [ { "name" => "first_name", "description" => "The billing contact's first name" },
                   { "name" => "organization_name", "description" => "The organization" },
                   { "name" => "month", "description" => "e.g. October 2026" },
                   { "name" => "total_paid", "description" => "What they paid CocoScout that month" },
                   { "name" => "opening", "description" => "CocoScout balance at the start of the month" },
                   { "name" => "closing", "description" => "CocoScout balance at the end of the month" },
                   { "name" => "billing_url", "description" => "Their Billing & Plan page" } ] },
    { key: "cocoscout_bill", name: "CocoScout bill issued", channel: "email",
      subject: "Your CocoScout bill: {{bill_title}}, {{amount}}",
      body: %(<p>Hi {{first_name}},</p><p>Here's {{organization_name}}'s CocoScout bill for <strong>{{bill_title}}</strong>: {{amount}}.</p>{{lines}}<p>{{how_paid}}</p><p>The invoice is attached (<a href="{{invoice_url}}">download it again</a>). Every bill is on your <a href="{{billing_url}}">Billing &amp; Plan page</a>.</p>),
      variables: [ { "name" => "first_name", "description" => "The billing contact's first name" },
                   { "name" => "organization_name", "description" => "The organization" },
                   { "name" => "bill_title", "description" => "What the bill is for, e.g. September 2026 usage" },
                   { "name" => "amount", "description" => "The amount, e.g. $41.00" },
                   { "name" => "lines", "description" => "What's on the bill, line by line" },
                   { "name" => "how_paid", "description" => "How and when it's paid" },
                   { "name" => "invoice_url", "description" => "CocoScout's invoice for the bill (PDF)" },
                   { "name" => "billing_url", "description" => "Their Billing & Plan page" } ] },
    { key: "cocoscout_bill_paid", name: "CocoScout bill paid (receipt)", channel: "email",
      subject: "Receipt: {{bill_title}}, {{amount}} paid",
      body: %(<p>Hi {{first_name}},</p><p>Your CocoScout bill for <strong>{{bill_title}}</strong> is paid: {{amount}}, on {{paid_on}}. Thank you.</p>{{lines}}<p>The invoice, marked paid, is attached (<a href="{{invoice_url}}">download it again</a>). Every bill is on your <a href="{{billing_url}}">Billing &amp; Plan page</a>.</p>),
      variables: [ { "name" => "first_name", "description" => "The billing contact's first name" },
                   { "name" => "organization_name", "description" => "The organization" },
                   { "name" => "bill_title", "description" => "What the bill is for, e.g. September 2026 usage" },
                   { "name" => "amount", "description" => "The amount paid, e.g. $41.00" },
                   { "name" => "paid_on", "description" => "The day it was paid" },
                   { "name" => "lines", "description" => "What was on the bill, line by line" },
                   { "name" => "invoice_url", "description" => "CocoScout's invoice for the bill (PDF)" },
                   { "name" => "billing_url", "description" => "Their Billing & Plan page" } ] }
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
