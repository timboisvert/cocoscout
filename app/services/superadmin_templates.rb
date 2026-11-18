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
                   { "name" => "finances_url", "description" => "The organization's page in Superadmin → Finances" } ] },
    { key: "superadmin_follower_email_block_bought", name: "Extra follower emails bought (to superadmins)", channel: "message",
      subject: "{{organization_name}} bought {{emails}} extra emails to followers for {{price}}",
      body: %(<p><strong>{{organization_name}}</strong> bought {{emails}} extra emails to followers for {{price}}. It goes on their next bill.</p><p><a href="{{email_url}}">Open Email in Superadmin</a></p>),
      variables: [ { "name" => "organization_name", "description" => "The organization" },
                   { "name" => "emails", "description" => "How many emails the block holds" },
                   { "name" => "price", "description" => "What it costs" },
                   { "name" => "email_url", "description" => "Superadmin → Finances → Email" } ] },
    { key: "superadmin_mail_volume_close", name: "Mail close to the Mailgun plan (to superadmins)", channel: "message",
      subject: "CocoScout has sent {{sent}} of the {{plan}} emails in this month's Mailgun plan",
      body: %(<p>CocoScout has sent {{sent}} emails in {{month}}, {{percent}}% of the {{plan}} its Mailgun plan includes. Mail past the plan still goes out, at Mailgun's price for each extra thousand.</p><p><a href="{{email_url}}">Open Email in Superadmin</a></p>),
      variables: [ { "name" => "sent", "description" => "Emails sent this month" }, { "name" => "plan", "description" => "What the plan includes" },
                   { "name" => "percent", "description" => "Sent as a share of the plan" }, { "name" => "month", "description" => "The month" },
                   { "name" => "email_url", "description" => "Superadmin → Finances → Email" } ] },
    { key: "superadmin_mail_upgrade_near", name: "Time to move up a Mailgun plan (to superadmins)", channel: "message",
      subject: "At this pace CocoScout will send about {{projected}} emails in {{month}}: time to move up a Mailgun plan",
      body: %(<p>At the pace so far, CocoScout will send about {{projected}} emails in {{month}}. Past {{upgrade_at}} a month the next Mailgun plan costs less than paying for the extra on this one.</p><p><a href="{{email_url}}">Open Email in Superadmin</a></p>),
      variables: [ { "name" => "projected", "description" => "Where the month is heading" }, { "name" => "upgrade_at", "description" => "The volume past which the next plan is cheaper" },
                   { "name" => "month", "description" => "The month" }, { "name" => "email_url", "description" => "Superadmin → Finances → Email" } ] }
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
