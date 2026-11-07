# frozen_string_literal: true

# The rest of the staffing notices plan (Tim, 2026-11-07, "do it all"):
#
# - Every organization has a time zone (Central, as the app always assumed,
#   until it picks another), so its pages, forms, notices and reminders read
#   in its own clock. Four of the fifteen organizations are outside Central.
# - A reminder the afternoon before a shift, sent once per row (reminded_at).
# - "Hours approved": the notice the Pay group's description promised.
class StaffRemindersHoursApprovedAndTimeZones < ActiveRecord::Migration[8.1]
  class Template < ActiveRecord::Base
    self.table_name = "content_templates"
  end

  CENTRAL = "Central Time (US & Canada)"

  TEMPLATES = [
    { key: "staff_shift_reminder", name: "Shift reminder (staff)", category: "shows", channel: "both",
      subject: "Tomorrow: {{headline}}",
      push_body: "Tomorrow: {{headline}}",
      body: "<p>Hi {{recipient_name}}, a reminder for tomorrow, {{shift_day}}, at {{organization_name}}:</p>" \
            "<ul>{{shifts_list}}</ul>" \
            "<p><a href=\"{{shift_url}}\">See this shift</a></p>" \
            "<p>If something's come up, say so on My Shifts so the team can sort out cover.</p>" },
    { key: "staff_hours_approved", name: "Hours approved (staff)", category: "shows", channel: "both",
      subject: "Hours approved: {{hours_words}}{{#amount}} · {{amount}}{{/amount}}",
      push_body: "{{organization_name}} approved {{hours_words}}{{#amount}} · {{amount}}{{/amount}}",
      body: "<p>Hi {{recipient_name}}, {{organization_name}} approved your hours:</p>" \
            "<ul>{{entries_list}}</ul>" \
            "<p>{{next_line}}</p>" \
            "<p><a href=\"{{my_payments_link}}\">See your pay</a></p>" }
  ].freeze

  def up
    add_column :organizations, :time_zone, :string, null: false, default: CENTRAL
    add_column :shift_assignments, :reminded_at, :datetime

    TEMPLATES.each do |attrs|
      template = Template.find_or_initialize_by(key: attrs[:key])
      template.assign_attributes(attrs.merge(active: true, template_type: "structured"))
      template.save!
    end
  end

  def down
    Template.where(key: TEMPLATES.map { |t| t[:key] }).delete_all
    remove_column :shift_assignments, :reminded_at
    remove_column :organizations, :time_zone
  end
end
