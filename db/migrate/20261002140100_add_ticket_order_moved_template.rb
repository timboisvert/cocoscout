# frozen_string_literal: true

# The email a buyer gets when the theater moves their tickets to another
# date: the new tickets, and the refunded difference when the new ones cost
# less.
class AddTicketOrderMovedTemplate < ActiveRecord::Migration[8.1]
  TEMPLATE = {
    key: "ticket_order_moved",
    name: "Tickets Moved to Another Date",
    subject: "Your tickets moved to {{show_date}}: {{show_title}}",
    body: <<~HTML,
      <p>Hi {{first_name}},</p>
      <p>Your {{ticket_count}} for <strong>{{show_title}}</strong> moved to {{show_date}} at {{show_time}}{{#venue}}, at {{venue}}{{/venue}}. They were for {{was}}.</p>
      {{#refund_amount}}<p>The new tickets cost less, so we refunded the {{refund_amount}} difference to the card you paid with. It usually shows up within 5 to 10 business days.</p>{{/refund_amount}}
      <p>Here are your new tickets. The old ones no longer work.</p>
      <p style="color:#6b7280;font-size:12px">Order {{order_code}} · <a href="{{order_url}}">View your order</a></p>
    HTML
    variables: [
      { "name" => "first_name", "description" => "Buyer's first name" },
      { "name" => "organization_name", "description" => "The theater selling the tickets" },
      { "name" => "show_title", "description" => "The show's title" },
      { "name" => "show_date", "description" => "The new day and date" },
      { "name" => "show_time", "description" => "The new start time" },
      { "name" => "venue", "description" => "The venue and room" },
      { "name" => "was", "description" => "The date and time the tickets were for" },
      { "name" => "refund_amount", "description" => "The difference refunded, when the new tickets cost less" },
      { "name" => "ticket_count", "description" => "e.g. 2 tickets" },
      { "name" => "order_code", "description" => "The new order's short code" },
      { "name" => "order_url", "description" => "Link to the buyer's new order" }
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
