# frozen_string_literal: true

# The words of the notifications CocoScout's superadmins get about the
# business (SuperadminNotices; Tim, 2026-11-14): a new organization, and an
# organization starting to pay for Pro. Each is a seeded ContentTemplate (the
# PlatformTemplates pattern) and a notification only: the Notifications list
# and a push, never an email. The subject is what the notification says; the
# body is kept for the template's editor and says the same.
class SuperadminTemplates
  TEMPLATES = [
    { key: "superadmin_organization_created", name: "New organization (to superadmins)", channel: "message",
      subject: "New organization: {{organization_name}}, made by {{owner_name}}",
      body: %(<p>{{owner_name}} made a new organization on CocoScout: <strong>{{organization_name}}</strong>.</p><p><a href="{{organization_url}}">Open it in Superadmin</a></p>),
      variables: [ { "name" => "organization_name", "description" => "The new organization" },
                   { "name" => "owner_name", "description" => "Who made it: their name, else their email" },
                   { "name" => "organization_url", "description" => "The organization in Superadmin" } ] },
    { key: "superadmin_pro_started", name: "Organization started Pro (to superadmins)", channel: "message",
      subject: "{{organization_name}} started {{plan}}",
      body: %(<p><strong>{{organization_name}}</strong> started paying for CocoScout Pro: {{plan}}.</p><p><a href="{{finances_url}}">Open its finances in Superadmin</a></p>),
      variables: [ { "name" => "organization_name", "description" => "The organization" },
                   { "name" => "plan", "description" => "Which Pro, e.g. Pro, yearly or Pro on the monthly bill" },
                   { "name" => "finances_url", "description" => "The organization's page in Superadmin → Finances" } ] }
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
