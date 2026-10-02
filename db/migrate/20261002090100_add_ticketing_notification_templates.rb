# frozen_string_literal: true

# The words of Ticketing's notices to the theater (TicketingNotifier): one
# template per kind, emailed to whoever the theater chose in Ticketing
# settings → Notifications. Lists (a day's sales, upcoming shows) arrive as
# ready-made rows in a variable; everything else is plain words.
class AddTicketingNotificationTemplates < ActiveRecord::Migration[8.1]
  FOOTER = %(<p style="color:#6b7280;font-size:12px">You get these because {{organization_name}} chose you in Ticketing settings. <a href="{{settings_url}}">Change what you get</a></p>)

  SHOW = [
    { "name" => "show_title", "description" => "The show's title" },
    { "name" => "show_date", "description" => "Day and date, e.g. Friday, October 10" },
    { "name" => "show_time", "description" => "Start time" },
    { "name" => "show_url", "description" => "The show's page in Ticketing" }
  ].freeze

  TEMPLATES = [
    { key: "ticketing_sale", name: "Ticketing: each sale",
      subject: "{{ticket_count}} sold: {{show_title}}, {{show_date}}",
      body: %(<p>{{buyer_name}} bought {{ticket_summary}} for <strong>{{show_title}}</strong> on {{show_date}}.</p><p>They paid {{order_total}}; you keep {{org_net}}. {{sold_line}}.</p><p><a href="{{order_url}}">See the order</a> · <a href="{{show_url}}">See the show</a></p>),
      vars: %w[buyer_name ticket_count ticket_summary order_total org_net sold_line order_url] },
    { key: "ticketing_daily_summary", name: "Ticketing: daily summary",
      subject: "Ticket sales for {{date_label}}: {{tickets_sold}} sold",
      body: %(<p>{{date_label}}: {{tickets_sold}} sold, {{ticket_sales}} in ticket sales{{#refunded}}, {{refunded}} refunded{{/refunded}}.</p>{{sales_rows}}<p><strong>Coming up</strong></p>{{upcoming_rows}}<p><a href="{{ticketing_url}}">Open Ticketing</a></p>),
      vars: %w[date_label tickets_sold ticket_sales refunded sales_rows upcoming_rows] },
    { key: "ticketing_show_day", name: "Ticketing: show day",
      subject: "Today: {{show_title}}, {{sold_line}}",
      body: %(<p><strong>{{show_title}}</strong> is today at {{show_time}}. {{sold_line}}{{#comps}}, including {{comps}} comps{{/comps}}.</p><p><a href="{{door_list_url}}">Print the door list</a> · <a href="{{show_url}}">See the show</a></p>),
      vars: %w[sold_line comps door_list_url] },
    { key: "ticketing_after_show", name: "Ticketing: after the show",
      subject: "{{show_title}}, {{show_date}}: {{checked_in}} came",
      body: %(<p><strong>{{show_title}}</strong> on {{show_date}}: {{sold}} tickets, {{checked_in}} checked in{{#no_shows}}, {{no_shows}} didn't come{{/no_shows}}.</p><p>Ticket sales {{ticket_sales}}; you keep {{org_net}}, now in your available balance.</p><p><a href="{{show_url}}">See the show</a></p>),
      vars: %w[sold checked_in no_shows ticket_sales org_net] },
    { key: "ticketing_sold_out", name: "Ticketing: sold out",
      subject: "Sold out: {{what}}, {{show_title}} on {{show_date}}",
      body: %(<p>{{what}} for <strong>{{show_title}}</strong> on {{show_date}} just sold out.</p><p><a href="{{show_url}}">See the show</a></p>),
      vars: %w[what] },
    { key: "ticketing_almost_sold_out", name: "Ticketing: almost sold out",
      subject: "Only {{remaining}} left: {{show_title}}, {{show_date}}",
      body: %(<p><strong>{{show_title}}</strong> on {{show_date}} has {{remaining}} seats left. {{sold_line}}.</p><p><a href="{{show_url}}">See the show</a></p>),
      vars: %w[remaining sold_line] },
    { key: "ticketing_sales_opened", name: "Ticketing: sales opened",
      subject: "On sale now: {{show_title}}, {{show_date}}",
      body: %(<p>Tickets for <strong>{{show_title}}</strong> on {{show_date}} are on sale now, as scheduled.</p><p><a href="{{public_url}}">The ticket page</a> · <a href="{{show_url}}">See the show</a></p>),
      vars: %w[public_url] },
    { key: "ticketing_refund_issued", name: "Ticketing: refund given",
      subject: "Refund: {{amount}} to {{buyer_name}}",
      body: %(<p>{{refunded_by}} refunded {{amount}} for {{ticket_count}} to <strong>{{show_title}}</strong> on {{show_date}}{{#reason}} ({{reason}}){{/reason}}.</p><p><a href="{{order_url}}">See the order</a></p>),
      vars: %w[refunded_by amount buyer_name ticket_count reason order_url] },
    { key: "ticketing_refund_problem", name: "Ticketing: refund problem",
      subject: "A refund didn't go through: {{buyer_name}}",
      body: %(<p>Refunding {{amount}} to {{buyer_name}} for <strong>{{show_title}}</strong> on {{show_date}} didn't go through: {{problem}}</p><p>They haven't been refunded yet. <a href="{{order_url}}">Open the order</a> to try again.</p>),
      vars: %w[amount buyer_name problem order_url] },
    { key: "ticketing_dispute", name: "Ticketing: disputed charge",
      subject: "{{headline}}: {{buyer_name}}, {{amount}}",
      body: %(<p>{{explanation}}</p><p>Order {{order_code}} for <strong>{{show_title}}</strong> on {{show_date}}. <a href="{{order_url}}">See the order</a></p>),
      vars: %w[headline explanation buyer_name amount order_code order_url] },
    { key: "ticketing_withdrawal", name: "Ticketing: withdrawal",
      subject: "{{headline}}",
      body: %(<p>{{explanation}}</p><p><a href="{{balance_url}}">Your CocoScout balance</a></p>),
      vars: %w[headline explanation balance_url] },
    { key: "ticketing_cancellation_done", name: "Ticketing: show cancellation done",
      subject: "{{show_title}}, {{show_date}}: {{refunded_count}} refunded",
      body: %(<p>Canceling <strong>{{show_title}}</strong> on {{show_date}} is done: {{refunded_count}} refunded, {{refunded_amount}} in all.{{#failed_count}} {{failed_count}} couldn't be refunded; open each order to try again.{{/failed_count}}</p><p><a href="{{orders_url}}">Orders for this show</a></p>),
      vars: %w[refunded_count refunded_amount failed_count orders_url] }
  ].freeze

  def up
    TEMPLATES.each do |spec|
      ContentTemplate.find_or_create_by!(key: spec[:key]) do |t|
        t.name = spec[:name]
        t.category = "ticketing"
        t.channel = "email"
        t.template_type = "structured"
        t.active = true
        t.subject = spec[:subject]
        t.body = spec[:body] + FOOTER
        t.available_variables = SHOW + spec[:vars].map { |name| { "name" => name, "description" => name.humanize } } +
                                [ { "name" => "organization_name", "description" => "The theater" },
                                  { "name" => "settings_url", "description" => "Where to change these emails" },
                                  { "name" => "ticketing_url", "description" => "Ticketing's home" } ]
      end
    end
  end

  def down
    ContentTemplate.where(key: TEMPLATES.map { |t| t[:key] }).destroy_all
  end
end
