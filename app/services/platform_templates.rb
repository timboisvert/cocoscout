# frozen_string_literal: true

# The words of the emails CocoScout sends about its own money, in one place
# (as TicketingTemplates and CourseTemplates are for theirs). Each is a
# seeded ContentTemplate.
class PlatformTemplates
  TEMPLATES = [
    { key: "cocoscout_money_check", name: "CocoScout money check needs a look", channel: "email",
      subject: "CocoScout's money check: {{headline}}",
      body: %(<p>This morning's check of CocoScout's Stripe balance against its records needs a look.</p>{{findings}}<p><a href="{{check_url}}">Open the Stripe check</a></p>),
      variables: [ { "name" => "headline", "description" => "One line: what's off" },
                   { "name" => "findings", "description" => "A list of what the check found" },
                   { "name" => "check_url", "description" => "The superadmin Stripe check page" } ] },
    { key: "org_monthly_statement", name: "Monthly CocoScout statement", channel: "email",
      subject: "Your CocoScout statement for {{month}}",
      body: %(<p>Hi {{first_name}},</p><p>Here's {{organization_name}}'s CocoScout statement for {{month}}. You paid CocoScout {{total_paid}}, and your CocoScout balance went from {{opening}} to {{closing}}. The statement is attached, and every statement is on your <a href="{{billing_url}}">Billing &amp; Plan page</a>.</p>),
      variables: [ { "name" => "first_name", "description" => "The owner's first name" },
                   { "name" => "organization_name", "description" => "The organization" },
                   { "name" => "month", "description" => "e.g. October 2026" },
                   { "name" => "total_paid", "description" => "What they paid CocoScout that month" },
                   { "name" => "opening", "description" => "CocoScout balance at the start of the month" },
                   { "name" => "closing", "description" => "CocoScout balance at the end of the month" },
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
