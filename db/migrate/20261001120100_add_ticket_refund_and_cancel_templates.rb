# frozen_string_literal: true

# The words of the two emails a buyer gets when money comes back: a refund
# the theater issued, and a show the theater canceled (that one is a draft the
# manager can edit before it goes to everyone).
class AddTicketRefundAndCancelTemplates < ActiveRecord::Migration[8.1]
  VARIABLES = [
    { "name" => "first_name", "description" => "Buyer's first name" },
    { "name" => "organization_name", "description" => "The theater selling the tickets" },
    { "name" => "show_title", "description" => "The show's title" },
    { "name" => "show_date", "description" => "Day and date, e.g. Friday, October 10" },
    { "name" => "show_time", "description" => "Start time, e.g. 7:30 PM" },
    { "name" => "refund_amount", "description" => "What comes back, e.g. $42.53" },
    { "name" => "ticket_count", "description" => "e.g. 2 tickets" },
    { "name" => "order_code", "description" => "The order's short code" },
    { "name" => "order_url", "description" => "Link to the buyer's order" }
  ].freeze

  def up
    ContentTemplate.find_or_create_by!(key: "ticket_order_refunded") do |t|
      t.name = "Ticket Order Refunded"
      t.category = "ticketing"
      t.channel = "email"
      t.template_type = "structured"
      t.active = true
      t.subject = "Your refund from {{organization_name}}"
      t.body = <<~HTML
        <p>Hi {{first_name}},</p>
        <p>{{organization_name}} refunded {{refund_amount}} for {{ticket_count}} to <strong>{{show_title}}</strong> on {{show_date}}. It goes back to the card you paid with and usually shows up within 5 to 10 business days.</p>
        <p>Order {{order_code}} · <a href="{{order_url}}">View your order</a></p>
      HTML
      t.available_variables = VARIABLES
    end

    ContentTemplate.find_or_create_by!(key: "ticket_event_canceled") do |t|
      t.name = "Ticketed Show Canceled"
      t.category = "ticketing"
      t.channel = "email"
      t.template_type = "structured"
      t.active = true
      t.subject = "{{show_title}} on {{show_date}} is canceled"
      t.body = <<~HTML
        <p>Hi {{first_name}},</p>
        <p>We're sorry: <strong>{{show_title}}</strong> on {{show_date}} at {{show_time}} is canceled.</p>
        <p>We've refunded {{refund_amount}} for your {{ticket_count}} to the card you paid with. It usually shows up within 5 to 10 business days.</p>
        <p>We hope to see you at another show soon.</p>
        <p>{{organization_name}}</p>
      HTML
      t.available_variables = VARIABLES
    end
  end

  def down
    ContentTemplate.where(key: %w[ticket_order_refunded ticket_event_canceled]).destroy_all
  end
end
