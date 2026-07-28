# frozen_string_literal: true

# ContentTemplate for the staff scheduling notification (publish + targeted
# updates). In-app message channel, matching how staff are notified today. All
# copy flows through ContentTemplateService — edit the seeded template, never
# hardcode. The per-person shift list and any removals are injected as
# pre-rendered (self-escaped) HTML variables.
class AddStaffScheduleNotificationTemplate < ActiveRecord::Migration[8.1]
  KEY = "staff_schedule_notification"

  BODY = <<~HTML
    <p>{{intro}}</p>
    {{#shifts_list}}<ul style="padding-left:18px;margin:8px 0;">{{shifts_list}}</ul>{{/shifts_list}}
    {{#removals_list}}<p style="margin:10px 0 4px;"><strong>No longer scheduled:</strong></p><ul style="padding-left:18px;margin:0 0 8px;">{{removals_list}}</ul>{{/removals_list}}
    <p>See all your shifts any time on your <a href="{{my_shifts_link}}">My Shifts</a> page.</p>
  HTML

  VARIABLES = [
    { "name" => "recipient_name",    "description" => "The staff member's first name" },
    { "name" => "organization_name", "description" => "The organization sending the schedule" },
    { "name" => "week_label",        "description" => "The week being scheduled, e.g. 'July 28'" },
    { "name" => "intro",             "description" => "The manager's editable intro line (escaped)" },
    { "name" => "shifts_list",       "description" => "Pre-rendered <li> list of the person's shifts (omitted when none)" },
    { "name" => "removals_list",     "description" => "Pre-rendered <li> list of removed shifts (omitted when none)" },
    { "name" => "my_shifts_link",    "description" => "URL to the person's My Shifts page" }
  ].freeze

  def up
    return if ContentTemplate.exists?(key: KEY)

    ContentTemplate.create!(
      key: KEY,
      name: "Staff Schedule Notification",
      subject: "Your work schedule — week of {{week_label}}",
      body: BODY,
      category: "shows",
      channel: "message",
      template_type: "hybrid",
      active: true,
      available_variables: VARIABLES
    )
  end

  def down
    ContentTemplate.find_by(key: KEY)&.destroy
  end
end
