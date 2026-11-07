# frozen_string_literal: true

# Staff shift notices, one per thing that happened to a person
# (~/.claude/plans/cocoscout-staffing-notifications.md, Tim 2026-11-07):
#
# - shift_assignments remember what the person was told (told_*), stamped
#   with notified_at, so "changed" means the shift differs from that, not
#   that the row was touched. Rows already told are backfilled from their
#   shift as it stands: nobody gets a "changed" notice for nothing.
# - staff_schedule_removals keep the shift's end too, so the notice can say
#   the hours.
# - Five new templates (a new shift, a changed one, one they're no longer
#   on, several changes at once, a claimed cover shift), and new words for
#   the ones that could say something untrue (§4 of the plan): the weekly
#   notice emails at once and never promises cover; shift off / moved say
#   what remains that day and follow the manager's tick; the cover notices
#   say "put on" when a manager assigned by hand.
class StaffShiftNotices < ActiveRecord::Migration[8.1]
  class Template < ActiveRecord::Base
    self.table_name = "content_templates"
  end

  def up
    add_column :shift_assignments, :told_starts_at, :datetime
    add_column :shift_assignments, :told_ends_at, :datetime
    add_column :shift_assignments, :told_role_label, :string
    add_column :shift_assignments, :told_location_name, :string
    add_column :staff_schedule_removals, :shift_ends_at, :datetime

    # What a told row was told: the shift as it is now (role label from the
    # primary role; extra roles are rare and a later edit re-tells anyway).
    execute <<~SQL
      UPDATE shift_assignments a
         SET told_starts_at = s.starts_at,
             told_ends_at = s.ends_at,
             told_role_label = r.name,
             told_location_name = l.name
        FROM shifts s
        JOIN house_roles r ON r.id = s.house_role_id
        LEFT JOIN locations l ON l.id = r.location_id
       WHERE a.shift_id = s.id AND a.notified_at IS NOT NULL
    SQL

    TEMPLATES.each do |attrs|
      template = Template.find_or_initialize_by(key: attrs[:key])
      template.assign_attributes(attrs.merge(active: true, template_type: attrs[:template_type] || "structured"))
      template.save!
    end
  end

  def down
    remove_column :shift_assignments, :told_starts_at
    remove_column :shift_assignments, :told_ends_at
    remove_column :shift_assignments, :told_role_label
    remove_column :shift_assignments, :told_location_name
    remove_column :staff_schedule_removals, :shift_ends_at
    Template.where(key: %w[staff_shift_added staff_shift_changed staff_shift_removed staff_schedule_changes shift_claim_confirmed]).delete_all
  end

  SHIFT_VARS = [
    { "name" => "recipient_name", "description" => "The staff member's first name" },
    { "name" => "organization_name", "description" => "The organization" },
    { "name" => "role_label", "description" => "The shift's role(s), e.g. Bartender + Door" },
    { "name" => "shift_day", "description" => "The day in full, e.g. Friday, Nov 13" },
    { "name" => "shift_date_short", "description" => "The day, short, e.g. Fri Nov 13" },
    { "name" => "shift_hours", "description" => "The hours, e.g. 6:00–11:30 PM" },
    { "name" => "start_time", "description" => "When it starts, e.g. 6:00 PM" },
    { "name" => "location_name", "description" => "Where, when the role or booking has a place" },
    { "name" => "shows_line", "description" => "The shows that day, e.g. \"That night: Rising Stars (7:30 PM)\"; blank when the shift has none" },
    { "name" => "shift_url", "description" => "My Shifts, landing on this shift" },
    { "name" => "my_shifts_link", "description" => "My Shifts" }
  ].freeze

  TEMPLATES = [
    {
      key: "staff_schedule_notification", name: "Staff Schedule Notification", category: "shows", channel: "both", template_type: "hybrid",
      description: "The week's shifts, sent to each person the first time a week is published and on Resend.",
      subject: "Your work schedule — week of {{week_label}}",
      push_body: "Your shifts for the week of {{week_label}} are set · {{shift_count_words}}",
      body: <<~HTML,
        <p>{{intro}}</p>
        {{#shifts_list}}<ul style="padding-left:18px;margin:8px 0;">{{shifts_list}}</ul>{{/shifts_list}}
        {{#removals_list}}<p style="margin:10px 0 4px;"><strong>No longer scheduled:</strong></p><ul style="padding-left:18px;margin:0 0 8px;">{{removals_list}}</ul>{{/removals_list}}
        <p>If you can't make one, say so on <a href="{{my_shifts_link}}">My Shifts</a> so the team can sort out cover.</p>
      HTML
      available_variables: [
        { "name" => "recipient_name", "description" => "The staff member's first name" },
        { "name" => "organization_name", "description" => "The organization sending the schedule" },
        { "name" => "week_label", "description" => "The week, e.g. November 10" },
        { "name" => "shift_count_words", "description" => "How many shifts, e.g. 3 shifts" },
        { "name" => "intro", "description" => "The manager's editable intro line" },
        { "name" => "shifts_list", "description" => "The person's shifts, one list item each, linked (blank when none)" },
        { "name" => "removals_list", "description" => "Shifts they're no longer on, one list item each (blank when none)" },
        { "name" => "my_shifts_link", "description" => "My Shifts" }
      ]
    },
    {
      key: "staff_shift_added", name: "Shift added (staff)", category: "shows", channel: "both",
      description: "Notify updates: the one shift this person was added to since they were last told.",
      subject: "New shift: {{role_label}}, {{shift_day}}",
      push_body: "New shift: {{role_label}}, {{shift_date_short}}, {{shift_hours}}{{#location_name}} at {{location_name}}{{/location_name}}",
      body: <<~HTML,
        <p>Hi {{recipient_name}},</p>
        <p>{{organization_name}} put you on <strong>{{role_label}}</strong>, <strong>{{shift_day}}, {{shift_hours}}</strong>{{#location_name}} at {{location_name}}{{/location_name}}.</p>
        {{#shows_line}}<p>{{shows_line}}</p>{{/shows_line}}
        <p><a href="{{shift_url}}">See this shift</a></p>
        <p>If you can't make it, say so on My Shifts so the team can sort out cover.</p>
      HTML
      available_variables: SHIFT_VARS
    },
    {
      key: "staff_shift_changed", name: "Shift changed (staff)", category: "shows", channel: "both",
      description: "Notify updates: a shift this person was told about now differs (time, day, role or place), or they're on another shift that day instead.",
      subject: "{{change_title}}",
      push_body: "{{change_title}}",
      body: <<~HTML,
        <p>Hi {{recipient_name}},</p>
        <p><strong>{{role_label}}</strong>, {{shift_day}}{{#location_name}} at {{location_name}}{{/location_name}}:</p>
        {{changes_list}}
        <p><a href="{{shift_url}}">See this shift</a></p>
        <p>If the change doesn't work for you, say so on My Shifts so the team can sort out cover.</p>
      HTML
      available_variables: SHIFT_VARS + [
        { "name" => "change_title", "description" => "What changed, e.g. \"New time for your Bartender shift, Fri Nov 13: 5:30–11:00 PM\"" },
        { "name" => "changes_list", "description" => "Each change, was and now, as a list" }
      ]
    },
    {
      key: "staff_shift_removed", name: "No longer scheduled (staff)", category: "shows", channel: "both",
      description: "Notify updates: a shift this person had seen or been told about was taken off their schedule.",
      subject: "No longer scheduled: {{role_label}}, {{shift_day}}, {{start_time}}",
      push_body: "No longer scheduled: {{role_label}}, {{shift_date_short}}, {{start_time}}.{{#remaining_line}} {{remaining_line}}{{/remaining_line}}",
      body: <<~HTML,
        <p>Hi {{recipient_name}},</p>
        <p>Your <strong>{{role_label}}</strong> shift on <strong>{{shift_day}}, {{shift_hours}}</strong>{{#location_name}} at {{location_name}}{{/location_name}} has come off the schedule at {{organization_name}}{{#day_back}}, so you have that {{day_back}} back{{/day_back}}.</p>
        {{#remaining_list}}<p style="margin:10px 0 4px;"><strong>Still on your schedule that day</strong></p><ul style="padding-left:18px;margin:0 0 8px;">{{remaining_list}}</ul>{{/remaining_list}}
        {{#rest_list}}<p style="margin:10px 0 4px;"><strong>The rest of your week</strong></p><ul style="padding-left:18px;margin:0 0 8px;">{{rest_list}}</ul>{{/rest_list}}
        <p>Questions? Ask a manager at {{organization_name}}.</p>
        <p><a href="{{my_shifts_link}}">See your shifts</a></p>
      HTML
      available_variables: SHIFT_VARS + [
        { "name" => "remaining_line", "description" => "What's still on that day, e.g. \"You're still on Door that night, 8:00–11:00 PM.\"; blank when nothing" },
        { "name" => "remaining_list", "description" => "The shifts still on that day, as list items; blank when none" },
        { "name" => "day_back", "description" => "\"afternoon\" or \"evening\" when nothing else is on that day; blank otherwise" },
        { "name" => "rest_list", "description" => "Their other shifts this week, as list items; blank when none" }
      ]
    },
    {
      key: "staff_schedule_changes", name: "Several shift changes (staff)", category: "shows", channel: "both", template_type: "hybrid",
      description: "Notify updates: two or more things happened to one person's week, in sections.",
      subject: "Changes to your shifts, week of {{week_label}}",
      push_body: "{{count_words}} to your shifts, week of {{week_label}}: {{summary}}",
      body: <<~HTML,
        <p>{{intro}}</p>
        {{sections}}
        <p><a href="{{my_shifts_link}}">See your shifts</a></p>
        <p>If something doesn't work for you, say so on My Shifts so the team can sort out cover.</p>
      HTML
      available_variables: [
        { "name" => "recipient_name", "description" => "The staff member's first name" },
        { "name" => "organization_name", "description" => "The organization" },
        { "name" => "week_label", "description" => "The week, e.g. November 10" },
        { "name" => "count_words", "description" => "e.g. 3 changes" },
        { "name" => "summary", "description" => "e.g. 1 new, 1 changed, 1 no longer scheduled" },
        { "name" => "intro", "description" => "The manager's editable intro line" },
        { "name" => "sections", "description" => "New, Changed and No longer scheduled, each a heading and a list" },
        { "name" => "my_shifts_link", "description" => "My Shifts" }
      ]
    },
    {
      key: "shift_claim_confirmed", name: "Cover shift claimed (staff)", category: "staffing", channel: "both",
      description: "Sent the moment someone claims a cover shift from an invitation.",
      subject: "You've got the {{role_label}} shift on {{shift_day}}",
      push_body: "You've got the {{role_label}} shift, {{shift_date_short}}: {{shift_hours}}{{#location_name}} at {{location_name}}{{/location_name}}",
      body: <<~HTML,
        <p>Hi {{recipient_name}},</p>
        <p><strong>{{role_label}}</strong>, <strong>{{shift_day}}, {{shift_hours}}</strong>{{#location_name}} at {{location_name}}{{/location_name}} is yours. Thanks for covering for {{vacated_by_name}}.</p>
        {{#shows_line}}<p>{{shows_line}}</p>{{/shows_line}}
        <p><a href="{{shift_url}}">See this shift</a></p>
      HTML
      available_variables: SHIFT_VARS + [ { "name" => "vacated_by_name", "description" => "Who couldn't make it" } ]
    },
    {
      key: "shift_canceled", name: "Shift off (staff)", category: "shows", channel: "both",
      description: "Sent to staff when the show their shift was for is canceled or taken away.",
      subject: "{{organization_name}}: {{headline}}",
      push_body: "{{headline}}",
      body: <<~HTML,
        <p>Hi {{recipient_name}},</p>
        <p>{{what}}{{outcome}}:</p>
        <p>{{shifts}}</p>
        {{#remaining}}<p>{{remaining}}</p>{{/remaining}}
        <p>Questions? Ask a manager at {{organization_name}}.</p>
      HTML
      available_variables: [
        { "name" => "recipient_name", "description" => "The staff member's first name" },
        { "name" => "organization_name", "description" => "The organization" },
        { "name" => "dates", "description" => "The dates, short" },
        { "name" => "headline", "description" => "The short version, e.g. \"Shift off: Bartender, Fri Nov 13, 6:00 PM\"" },
        { "name" => "what", "description" => "What happened, e.g. \"Laugh-Along, Live! on Sat, Nov 1 was canceled\"" },
        { "name" => "outcome", "description" => "\", so this shift is off\", or that the shift stands for now when the shifts weren't taken off" },
        { "name" => "shifts", "description" => "Each shift: role, date and hours, one per line" },
        { "name" => "remaining", "description" => "What's still on that day, or that nothing else is; blank when the shift stands" }
      ]
    },
    {
      key: "shift_moved", name: "Shift moved (staff)", category: "shows", channel: "both",
      description: "Sent to staff when the show their shift is for moves.",
      subject: "{{organization_name}}: {{headline}}",
      push_body: "{{headline}}",
      body: <<~HTML,
        <p>Hi {{recipient_name}},</p>
        <p>{{what}}{{outcome}}:</p>
        <p>{{shifts}}</p>
        <p>If that doesn't work for you, say so on My Shifts so the team can sort out cover.</p>
      HTML
      available_variables: [
        { "name" => "recipient_name", "description" => "The staff member's first name" },
        { "name" => "organization_name", "description" => "The organization" },
        { "name" => "dates", "description" => "The dates, short" },
        { "name" => "headline", "description" => "The short version, e.g. \"New time: Bartender, Sat Nov 14, 8:30 PM\"" },
        { "name" => "what", "description" => "What moved, e.g. \"Laugh-Along, Live! moved to 8:30 PM\"" },
        { "name" => "outcome", "description" => "\", so your shift moved with it\", or that the shift keeps its hours when the shifts weren't moved" },
        { "name" => "shifts", "description" => "Each shift: role, date and hours (was and now), one per line" }
      ]
    },
    {
      key: "shift_vacancy_filled", name: "Shift covered", category: "staffing", channel: "both",
      description: "Someone is covering a shift a person couldn't make: to the chosen managers and to that person.",
      subject: "{{covering_subject}}",
      push_body: "{{covering_subject}}",
      body: "<p>{{covering_words}}</p><p><a href=\"{{link_url}}\">{{link_text}}</a></p>",
      available_variables: %w[person_name filled_by_name role_name shift_date shift_time organization_name covering_subject covering_words link_url link_text]
    }
  ].freeze
end
