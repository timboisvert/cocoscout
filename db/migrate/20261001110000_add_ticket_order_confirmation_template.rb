# frozen_string_literal: true

# The words of a ticket buyer's confirmation email. The tickets themselves
# (one QR code each) are added under this copy by TicketOrderMailer.
class AddTicketOrderConfirmationTemplate < ActiveRecord::Migration[8.1]
  def up
    ContentTemplate.find_or_create_by!(key: "ticket_order_confirmation") do |t|
      t.name = "Ticket Order Confirmation"
      t.category = "ticketing"
      t.channel = "email"
      t.template_type = "structured"
      t.active = true
      t.subject = "Your tickets for {{show_title}}"
      t.body = <<~HTML
        <p>Hi {{first_name}},</p>
        <p>You're going to <strong>{{show_title}}</strong> at {{organization_name}}: {{show_date}} at {{show_time}}, {{venue}}.</p>
        <p>Here {{ticket_count_verb}} your {{ticket_count}}. Show the codes below at the door, on your phone or printed.</p>
        <p>Order {{order_code}} · <a href="{{order_url}}">View your tickets</a></p>
      HTML
      t.available_variables = [
        { "name" => "first_name", "description" => "Buyer's first name" },
        { "name" => "organization_name", "description" => "The theater selling the tickets" },
        { "name" => "show_title", "description" => "The show's title" },
        { "name" => "show_date", "description" => "Day and date, e.g. Friday, October 10" },
        { "name" => "show_time", "description" => "Start time, e.g. 7:30 PM" },
        { "name" => "venue", "description" => "Venue and room" },
        { "name" => "ticket_count", "description" => "e.g. 2 tickets" },
        { "name" => "ticket_count_verb", "description" => "is or are, to match ticket_count" },
        { "name" => "order_code", "description" => "The order's short code" },
        { "name" => "order_url", "description" => "Link to the buyer's tickets" }
      ]
    end
  end

  def down
    ContentTemplate.where(key: "ticket_order_confirmation").destroy_all
  end
end
