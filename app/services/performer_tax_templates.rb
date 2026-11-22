# frozen_string_literal: true

# The words of a W-9 request to someone an organization pays who isn't on its
# staff, and its weekly reminder (Tim, 2026-11-22: notifications and email).
# Seeded ContentTemplates; the email carries the one button (EmailButton:
# class="button") to the page about their year.
class PerformerTaxTemplates
  VARIABLES = [
    { "name" => "first_name", "description" => "Their first name" },
    { "name" => "organization_name", "description" => "The organization paying them" },
    { "name" => "paid_words", "description" => "What it has paid them so far this year, e.g. $1,640" },
    { "name" => "threshold_words", "description" => "The 1099 amount for the year, e.g. $2,000" },
    { "name" => "tax_year", "description" => "The year, e.g. 2026" },
    { "name" => "overview_url", "description" => "Their page about the year, with the W-9 button" }
  ].freeze

  TEMPLATES = [
    { key: "performer_w9_request", name: "W-9 requested (to a performer or contract person paid personally)",
      subject: "{{organization_name}} needs a W-9 from you",
      push_body: "{{organization_name}} needs a W-9 from you. It takes about five minutes.",
      body: %(<p>Hi {{first_name}},</p>) +
            %(<p>{{organization_name}} has paid you {{paid_words}} so far in {{tax_year}}. When an organization pays someone {{threshold_words}} or more in a year, it sends them a Form 1099-NEC and reports the payments to the IRS, and it needs a Form W-9 from them to do that.</p>) +
            %(<p>The W-9 takes about five minutes, and you only fill it in once for {{organization_name}}. Only {{organization_name}} sees what you enter.</p>) +
            %(<p><a href="{{overview_url}}" class="button">See your year and fill in your W-9</a></p>) },
    { key: "performer_w9_reminder", name: "W-9 reminder (to a performer or contract person paid personally)",
      subject: "Reminder: {{organization_name}} still needs your W-9",
      push_body: "{{organization_name}} still needs your W-9.",
      body: %(<p>Hi {{first_name}},</p>) +
            %(<p>{{organization_name}} still needs a Form W-9 from you. It has paid you {{paid_words}} so far in {{tax_year}}, and it needs your W-9 to send you a Form 1099-NEC once your payments reach {{threshold_words}}.</p>) +
            %(<p><a href="{{overview_url}}" class="button">Fill in your W-9</a></p>) }
  ].freeze

  def self.ensure!(keys: nil, overwrite: false)
    TEMPLATES.each do |spec|
      next if keys && !keys.include?(spec[:key])

      template = ContentTemplate.find_or_initialize_by(key: spec[:key])
      next if template.persisted? && !overwrite

      template.assign_attributes(name: spec[:name], category: "payments", channel: "both", template_type: "structured",
                                 active: true, subject: spec[:subject], body: spec[:body], push_body: spec[:push_body],
                                 available_variables: VARIABLES)
      template.save!
    end
  end
end
