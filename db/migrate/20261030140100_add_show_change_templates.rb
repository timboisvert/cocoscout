# frozen_string_literal: true

# The words for telling people a show changed (docs/show_change_notices_plan.md):
# the cast when it moves (show_canceled already tells them of a cancel), and
# the staff when their shifts are off or moved. Each lists the person's own
# dates, one per line, so a series is one message.
class AddShowChangeTemplates < ActiveRecord::Migration[8.1]
  TEMPLATES = [
    {
      key: "show_moved",
      name: "Show moved (cast)",
      category: "shows",
      description: "Sent to the cast when a show they're cast in moves to another time.",
      subject: "[{{production_name}}] New time: {{dates}}",
      push_body: "{{production_name}} has a new time: {{dates}}",
      body: <<~HTML,
        <p>Hi {{recipient_name}},</p>
        <p>{{production_name}} has moved:</p>
        <p>{{changes}}</p>
        <p>You're still cast. If you can't make the new time, let the production team know as soon as you can.</p>
      HTML
      variables: [
        { "name" => "recipient_name", "description" => "The cast member's first name" },
        { "name" => "production_name", "description" => "The production" },
        { "name" => "dates", "description" => "The new dates, short" },
        { "name" => "changes", "description" => "Each date, was and now, one per line" }
      ]
    },
    {
      key: "shift_canceled",
      name: "Shift off (staff)",
      category: "shows",
      description: "Sent to staff when the show their shift was for is canceled or taken away.",
      subject: "{{organization_name}}: your shift on {{dates}} is off",
      push_body: "Your shift on {{dates}} is off",
      body: <<~HTML,
        <p>Hi {{recipient_name}},</p>
        <p>{{what}}, so this shift is off:</p>
        <p>{{shifts}}</p>
        <p>You don't need to come in. If you have questions, reply to this message.</p>
      HTML
      variables: [
        { "name" => "recipient_name", "description" => "The staff member's first name" },
        { "name" => "organization_name", "description" => "The organization" },
        { "name" => "dates", "description" => "The dates, short" },
        { "name" => "what", "description" => "What happened, e.g. \"Laugh-Along, Live! on Sat, Nov 1 was canceled\"" },
        { "name" => "shifts", "description" => "Each shift: role, date and hours, one per line" }
      ]
    },
    {
      key: "shift_moved",
      name: "Shift moved (staff)",
      category: "shows",
      description: "Sent to staff when the show their shift is for moves.",
      subject: "{{organization_name}}: new time for your shift on {{dates}}",
      push_body: "New time for your shift on {{dates}}",
      body: <<~HTML,
        <p>Hi {{recipient_name}},</p>
        <p>{{what}}. Your shift:</p>
        <p>{{shifts}}</p>
        <p>If you can't make the new time, say so on My Shifts or reply to this message.</p>
      HTML
      variables: [
        { "name" => "recipient_name", "description" => "The staff member's first name" },
        { "name" => "organization_name", "description" => "The organization" },
        { "name" => "dates", "description" => "The dates, short" },
        { "name" => "what", "description" => "What moved, e.g. \"Laugh-Along, Live! moved to 8:30 PM\"" },
        { "name" => "shifts", "description" => "Each shift: role, date and hours (was and now), one per line" }
      ]
    }
  ].freeze

  def up
    TEMPLATES.each do |attrs|
      ContentTemplate.find_or_create_by!(key: attrs[:key]) do |t|
        t.name = attrs[:name]
        t.category = attrs[:category]
        t.description = attrs[:description]
        t.channel = "both"
        t.template_type = "structured"
        t.active = true
        t.push = true
        t.push_body = attrs[:push_body]
        t.subject = attrs[:subject]
        t.body = attrs[:body]
        t.available_variables = attrs[:variables]
      end
    end
  end

  def down
    ContentTemplate.where(key: TEMPLATES.map { |t| t[:key] }).destroy_all
  end
end
