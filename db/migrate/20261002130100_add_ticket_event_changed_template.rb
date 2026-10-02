# frozen_string_literal: true

# The email buyers get when their show moves: a new date, time or place
# (TicketShowChange). The theater reads and edits it before it goes.
class AddTicketEventChangedTemplate < ActiveRecord::Migration[8.1]
  TEMPLATE = {
    key: "ticket_event_changed",
    name: "Ticketed Show Changed",
    subject: "{{show_title}}: new {{what_changed}}",
    body: <<~HTML,
      <p>Hi {{first_name}},</p>
      <p><strong>{{show_title}}</strong> has a new {{what_changed}}. It's now {{now}}.</p>
      <p>It was {{was}}.</p>
      <p>Your tickets still work, so there's nothing you need to do. If the change doesn't work for you, just reply to this email.</p>
      <p>{{organization_name}}</p>
    HTML
    variables: [
      { "name" => "first_name", "description" => "Buyer's first name" },
      { "name" => "organization_name", "description" => "The theater selling the tickets" },
      { "name" => "show_title", "description" => "The show's title" },
      { "name" => "what_changed", "description" => "date, time, place, or several, e.g. date and time" },
      { "name" => "now", "description" => "When and where it is now, e.g. Saturday, October 11 at 8:00 PM, at the Main Stage" },
      { "name" => "was", "description" => "When and where the buyer was told before" },
      { "name" => "show_date", "description" => "The new day and date" },
      { "name" => "show_time", "description" => "The new start time" },
      { "name" => "venue", "description" => "The venue and room now" },
      { "name" => "ticket_count", "description" => "e.g. 2 tickets" },
      { "name" => "order_code", "description" => "The order's short code" },
      { "name" => "order_url", "description" => "Link to the buyer's order" }
    ]
  }.freeze

  def up
    ContentTemplate.find_or_create_by!(key: TEMPLATE[:key]) do |t|
      t.name = TEMPLATE[:name]
      t.category = "ticketing"
      t.channel = "email"
      t.template_type = "structured"
      t.active = true
      t.subject = TEMPLATE[:subject]
      t.body = TEMPLATE[:body]
      t.available_variables = TEMPLATE[:variables]
    end
  end

  def down
    ContentTemplate.where(key: TEMPLATE[:key]).destroy_all
  end
end
