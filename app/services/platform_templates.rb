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
                   { "name" => "check_url", "description" => "The superadmin Stripe check page" } ] }
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
