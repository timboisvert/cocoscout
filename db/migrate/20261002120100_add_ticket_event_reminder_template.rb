# frozen_string_literal: true

# The reminder a buyer gets before their show (TicketOrderMailer#reminder).
# Their QR tickets follow the words, as in the confirmation.
class AddTicketEventReminderTemplate < ActiveRecord::Migration[8.1]
  TEMPLATE = {
    key: "ticket_event_reminder",
    name: "Ticket Reminder Before the Show",
    subject: "Reminder: {{show_title}} is {{when}}",
    body: <<~HTML,
      <p>Hi {{first_name}},</p>
      <p>See you {{when}}! <strong>{{show_title}}</strong> is {{show_date}} at {{show_time}}{{#venue}}, at {{venue}}{{/venue}}.</p>
      {{#address}}<p>{{address}} · <a href="{{directions_url}}">Directions</a></p>{{/address}}
      {{#door_note}}<p>{{door_note}}</p>{{/door_note}}
      <p>Your {{ticket_count}} {{ticket_count_verb}} below. Show them at the door, on your phone or printed.</p>
      <p style="color:#6b7280;font-size:12px">Order {{order_code}} · <a href="{{order_url}}">View your order</a> · <a href="{{stop_reminders_url}}">Stop reminder emails</a></p>
    HTML
    variables: [
      { "name" => "first_name", "description" => "Buyer's first name" },
      { "name" => "organization_name", "description" => "The theater selling the tickets" },
      { "name" => "show_title", "description" => "The show's title" },
      { "name" => "when", "description" => "tomorrow, on Friday, or on Friday, October 10" },
      { "name" => "show_date", "description" => "Day and date, e.g. Friday, October 10" },
      { "name" => "show_time", "description" => "Start time, e.g. 7:30 PM" },
      { "name" => "venue", "description" => "The venue and room" },
      { "name" => "address", "description" => "The venue's street address" },
      { "name" => "directions_url", "description" => "A map link to the venue" },
      { "name" => "door_note", "description" => "The show's note for the door, if it has one" },
      { "name" => "ticket_count", "description" => "e.g. 2 tickets" },
      { "name" => "ticket_count_verb", "description" => "is or are, to match the count" },
      { "name" => "order_code", "description" => "The order's short code" },
      { "name" => "order_url", "description" => "Link to the buyer's order" },
      { "name" => "stop_reminders_url", "description" => "Where the buyer turns reminders off for this order" }
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
