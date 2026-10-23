# frozen_string_literal: true

# Every word CocoScout writes around mailing lists (V1.1): the line at the
# bottom of each email to followers, the unsubscribe page, the starter draft
# for announcing a show, the note on a test send, the email telling someone a
# list was shared with them, and the one carrying an export. The manager's own
# emails are their own words. Seeded as ContentTemplates (the PlatformTemplates
# pattern); variables are escaped by the caller.
class FollowerTemplates
  TEMPLATES = [
    { key: "follower_email_footer", name: "Follower email: why they got it", channel: "email",
      subject: "Why you got this",
      body: "<p>You're getting this because you asked to hear from {{organization_name}}.</p>",
      variables: [ { "name" => "organization_name", "description" => "The organization sending it" } ] },
    { key: "follower_email_test_note", name: "Follower email: test send note", channel: "email",
      subject: "[Test] {{subject}}",
      body: "<p>This is a test of an email to your followers. They'll get it without this line, with their own first name.</p>",
      variables: [ { "name" => "subject", "description" => "The email's subject" } ] },
    { key: "follower_email_announce", name: "Follower email: announce a show", channel: "email",
      subject: "{{show_title}}: {{show_date}}",
      body: "<p>Hi {{first_name}},</p><p>{{show_title}} is {{show_date}} at {{show_time}}. We'd love to see you there.</p><p>See you soon,<br>{{organization_name}}</p>",
      variables: [ { "name" => "first_name", "description" => "Kept as is: filled in per follower when it's sent" },
                   { "name" => "show_title", "description" => "The show's title" },
                   { "name" => "show_date", "description" => "e.g. Friday, November 7" },
                   { "name" => "show_time", "description" => "e.g. 8:00 PM" },
                   { "name" => "organization_name", "description" => "The organization sending it" } ] },
    { key: "follower_unsubscribed_page", name: "Follower unsubscribe page", channel: "email",
      subject: "You're unsubscribed",
      body: "<p>You won't get emails from {{organization_name}} anymore. Your tickets and receipts still come as usual.</p>",
      variables: [ { "name" => "organization_name", "description" => "The organization they left" } ] },
    { key: "follower_resubscribed_page", name: "Follower resubscribe page", channel: "email",
      subject: "You're back on the list",
      body: "<p>{{organization_name}} will email you again. You can unsubscribe from any of their emails.</p>",
      variables: [ { "name" => "organization_name", "description" => "The organization they rejoined" } ] },
    { key: "follower_share_invitation", name: "Mailing list shared with you", channel: "email",
      subject: "{{organization_name}} shared {{list_name}} with you",
      body: "<p>Hi {{first_name}},</p><p>{{organization_name}} shared their mailing list <strong>{{list_name}}</strong> with you on CocoScout. It has {{follower_count}}. You'll find them in My Followers, where you can add people and export a spreadsheet.</p><p><a href=\"{{followers_url}}\">Open My Followers</a></p>",
      variables: [ { "name" => "first_name", "description" => "Their first name" },
                   { "name" => "organization_name", "description" => "The organization sharing it" },
                   { "name" => "list_name", "description" => "The list's name" },
                   { "name" => "follower_count", "description" => "e.g. 312 followers" },
                   { "name" => "followers_url", "description" => "My Followers" } ] },
    { key: "followers_export_ready", name: "Followers export ready", channel: "email",
      subject: "Your followers, as a spreadsheet",
      body: "<p>Hi {{first_name}},</p><p>Here's {{what}}: {{follower_count}}, with where each came from. The spreadsheet is attached.</p>",
      variables: [ { "name" => "first_name", "description" => "Their first name" },
                   { "name" => "what", "description" => "e.g. everyone in My Followers, or Dan Feltey's shows" },
                   { "name" => "follower_count", "description" => "e.g. 1,046 followers" } ] }
  ].freeze

  def self.ensure!(keys: nil, overwrite: false)
    TEMPLATES.each do |spec|
      next if keys && !keys.include?(spec[:key])

      template = ContentTemplate.find_or_initialize_by(key: spec[:key])
      next if template.persisted? && !overwrite

      template.assign_attributes(name: spec[:name], category: "mailing_lists", channel: spec[:channel], template_type: "structured",
                                 active: true, subject: spec[:subject], body: spec[:body], available_variables: spec[:variables])
      template.save!
    end
  end

  # Renders with every variable escaped.
  def self.render(key, variables = {})
    ContentTemplateService.render(key, variables.transform_values { |value| ERB::Util.html_escape(value.to_s) })
  end
end
