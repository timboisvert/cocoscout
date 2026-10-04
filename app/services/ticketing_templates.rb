# frozen_string_literal: true

# The words of every Ticketing email, in one place: what buyers get (their
# tickets, a reminder, a change, a move, a refund, a cancellation), what the
# theater gets (TicketingNotifier's notices), and the invitations. They're
# seeded as ContentTemplates — the superadmin can edit them — and rendered
# through ContentTemplateService, never hardcoded in a mailer.
#
# Bodies are one line each: ContentTemplate#format_html turns a newline
# into <br>. Blocks that are data, not words — a show's when-and-where, the
# tickets' QR codes, a sales table — are built by the mailer or arrive as
# ready-made HTML in a variable.
class TicketingTemplates
  FOOTER = %(<p style="color:#6b7280;font-size:12px;margin-top:20px">You get these because {{organization_name}} chose you in Ticketing settings. <a href="{{settings_url}}">Change what you get</a></p>)
  SHOW_VARS = [
    { "name" => "show_title", "description" => "The show's title" },
    { "name" => "show_date", "description" => "Day and date, e.g. Friday, October 10" },
    { "name" => "show_time", "description" => "Start time, e.g. 7:30 PM" },
    { "name" => "show_url", "description" => "The show's page in Ticketing" }
  ].freeze
  BUYER_VARS = [
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
  ].freeze

  def self.v(*names)
    names.map { |n| n.is_a?(Hash) ? n : { "name" => n.to_s, "description" => n.to_s.humanize } }
  end

  TEMPLATES = [
    # --- Buyers. The mailer adds the when-and-where block, the tickets (one
    # QR each), any products, and the order link under these words.
    { key: "ticket_order_confirmation", name: "Ticket Order Confirmation", channel: "email",
      subject: "Your tickets for {{show_title}}",
      body: %(<p>Hi {{first_name}},</p><p>You're going to <strong>{{show_title}}</strong> at {{organization_name}}. Here {{ticket_count_verb}} your {{ticket_count}}: show the codes below at the door, on your phone or printed.</p>),
      variables: BUYER_VARS },
    { key: "ticket_event_reminder", name: "Ticket Event Reminder", channel: "email",
      subject: "Reminder: {{show_title}} is {{when}}",
      body: %(<p>Hi {{first_name}},</p><p>See you {{when}}! Here's everything for <strong>{{show_title}}</strong>, and your {{ticket_count}} again — show them at the door, on your phone or printed.</p>),
      variables: BUYER_VARS + v({ "name" => "when", "description" => "tomorrow, on Friday, or on Friday, October 10" }) },
    { key: "ticket_event_changed", name: "Ticketed Show Changed", channel: "email",
      subject: "{{show_title}}: new {{what_changed}}",
      body: %(<p>Hi {{first_name}},</p><p><strong>{{show_title}}</strong> has a new {{what_changed}}. Your tickets were for {{was}}; here's where things stand now. They still work, so there's nothing you need to do. If the change doesn't work for you, just reply to this email.</p>),
      variables: BUYER_VARS + v({ "name" => "what_changed", "description" => "date, time, place, or a combination" }, { "name" => "was", "description" => "The date, time and place the buyer was told" }, { "name" => "now", "description" => "The date, time and place now" }) },
    { key: "ticket_order_moved", name: "Ticket Order Moved", channel: "email",
      subject: "Your tickets moved to {{show_date}}: {{show_title}}",
      body: %(<p>Hi {{first_name}},</p><p>{{organization_name}} moved your {{ticket_count}} for <strong>{{show_title}}</strong> to a new date. They were for {{was}}; here's the new one.</p>{{#refund_amount}}<p>The new tickets cost less, so we refunded the {{refund_amount}} difference to the card you paid with. It usually shows up within 5 to 10 business days.</p>{{/refund_amount}}<p>Your new tickets are below. The old ones no longer work.</p>),
      variables: BUYER_VARS + v({ "name" => "was", "description" => "The date and time the old tickets were for" }, { "name" => "refund_amount", "description" => "The difference refunded, if any" }) },
    { key: "ticket_order_refunded", name: "Ticket Order Refunded", channel: "email",
      subject: "Your refund from {{organization_name}}",
      body: %(<p>Hi {{first_name}},</p><p>{{organization_name}} refunded <strong>{{refund_amount}}</strong> for {{ticket_count}} to <strong>{{show_title}}</strong> on {{show_date}}. It goes back to the card you paid with and usually shows up within 5 to 10 business days.</p><p style="color:#6b7280;font-size:12px">Order {{order_code}} · <a href="{{order_url}}">View your order</a></p>),
      variables: BUYER_VARS + v({ "name" => "refund_amount", "description" => "What was refunded" }) },
    { key: "ticket_event_canceled", name: "Ticketed Show Canceled", channel: "email",
      subject: "{{show_title}} on {{show_date}} is canceled",
      body: %(<p>Hi {{first_name}},</p><p>We're sorry: <strong>{{show_title}}</strong> on {{show_date}} at {{show_time}} is canceled.</p><p>We've refunded {{refund_amount}} for your {{ticket_count}} to the card you paid with. It usually shows up within 5 to 10 business days.</p><p>We hope to see you at another show soon.</p><p>{{organization_name}}</p>),
      variables: BUYER_VARS + v({ "name" => "refund_amount", "description" => "What was refunded" }) },

    # --- The theater (TicketingNotifier). Tables arrive ready-made.
    { key: "ticketing_sale", name: "Ticketing: each sale", channel: "email",
      subject: "{{ticket_count}} sold: {{show_title}}, {{show_date}}",
      body: %(<p><strong>{{buyer_name}}</strong> bought {{ticket_summary}}{{#products}} and {{products}}{{/products}} for <strong>{{show_title}}</strong> on {{show_date}} at {{show_time}}.</p><p>They paid {{order_total}}; you keep {{org_net}}. {{sold_line}}{{#products_sold}} · {{products_sold}} sold so far{{/products_sold}}.</p><p><a href="{{order_url}}">View the order</a> · <a href="{{show_url}}">Open this show's ticketing</a></p>#{FOOTER}),
      variables: SHOW_VARS + v(:buyer_name, :ticket_count, :ticket_summary, :products, :order_total, :org_net, :sold_line, :products_sold, :order_url) },
    { key: "ticketing_daily_summary", name: "Ticketing: daily summary", channel: "email",
      subject: "Ticket sales for {{date_label}}: {{tickets_sold}} sold, {{ticket_sales}}",
      body: %(<p>Here's how ticketing went on <strong>{{date_label}}</strong>: {{tickets_sold}} tickets sold for {{ticket_sales}}{{#products_sold}}, plus {{products_sold}} for {{product_sales}}{{/products_sold}}{{#refunded}}; {{refunded}} refunded{{/refunded}}.</p>{{yesterday_table}}<h3 style="font-size:15px;margin:24px 0 8px">Coming up</h3>{{upcoming_table}}<p style="margin-top:16px"><a href="{{ticketing_url}}">Open Ticketing</a></p>#{FOOTER}),
      variables: v(:date_label, :tickets_sold, :ticket_sales, :products_sold, :product_sales, :refunded, :yesterday_table, :upcoming_table, :ticketing_url) },
    { key: "ticketing_show_day", name: "Ticketing: show day", channel: "email",
      subject: "Today: {{show_title}} — {{sold_line}}",
      body: %(<p><strong>{{show_title}}</strong> is today at {{show_time}}. {{sold_line}}{{#comps}}, {{comps}} of them comps{{/comps}}{{#products_sold}}; {{products_sold}} pre-bought{{/products_sold}}.</p>{{sales_table}}<p style="margin-top:16px"><a href="{{door_list_url}}">Print the door list</a> · <a href="{{show_url}}">Open this show's ticketing</a></p>#{FOOTER}),
      variables: SHOW_VARS + v(:sold_line, :comps, :products_sold, :sales_table, :door_list_url) },
    { key: "ticketing_after_show", name: "Ticketing: show summary", channel: "email",
      subject: "Show summary: {{show_title}}, {{show_date}}",
      body: %(<p><strong>{{show_title}}</strong> on {{show_date}}: {{sold}} tickets sold, {{checked_in}} checked in{{#no_shows}}, {{no_shows}} didn't come{{/no_shows}}{{#comps}}, {{comps}} comps{{/comps}}.</p>{{sales_table}}<p style="margin-top:16px">You keep <strong>{{org_net}}</strong>, now in your available balance.</p><p><a href="{{show_url}}">Open this show's ticketing</a></p>#{FOOTER}),
      variables: SHOW_VARS + v(:sold, :checked_in, :no_shows, :comps, :sales_table, :org_net) },
    { key: "ticketing_sold_out", name: "Ticketing: sold out", channel: "email",
      subject: "Sold out: {{what}}, {{show_title}} on {{show_date}}",
      body: %(<p>{{what}} for <strong>{{show_title}}</strong> on {{show_date}} just sold out. {{sold_line}}.</p><p><a href="{{show_url}}">Open this show's ticketing</a></p>#{FOOTER}),
      variables: SHOW_VARS + v(:what, :sold_line) },
    { key: "ticketing_almost_sold_out", name: "Ticketing: almost sold out", channel: "email",
      subject: "Only {{remaining}} left: {{show_title}}, {{show_date}}",
      body: %(<p><strong>{{show_title}}</strong> on {{show_date}} is nearly full: {{remaining}} seats left, {{sold_line}}.</p><p><a href="{{show_url}}">Open this show's ticketing</a></p>#{FOOTER}),
      variables: SHOW_VARS + v(:remaining, :sold_line) },
    { key: "ticketing_sales_opened", name: "Ticketing: sales opened", channel: "email",
      subject: "On sale now: {{show_title}}, {{show_date}}",
      body: %(<p>Tickets for <strong>{{show_title}}</strong> on {{show_date}} at {{show_time}} are on sale now, as scheduled.</p>{{tiers_table}}<p style="margin-top:16px"><a href="{{public_url}}">The ticket page</a> · <a href="{{show_url}}">Open this show's ticketing</a></p>#{FOOTER}),
      variables: SHOW_VARS + v(:tiers_table, :public_url) },
    { key: "ticketing_refund_issued", name: "Ticketing: refund given", channel: "email",
      subject: "Refund: {{amount}} to {{buyer_name}}",
      body: %(<p>{{refunded_by}} refunded <strong>{{amount}}</strong> to <strong>{{buyer_name}}</strong> for <strong>{{show_title}}</strong> on {{show_date}}: {{what}}{{#fees_kept}}, fees kept{{/fees_kept}}.{{#reason}} Note: {{reason}}.{{/reason}}</p><p>Order {{order_code}}. {{money_note}}</p><p><a href="{{order_url}}">View the order</a></p>#{FOOTER}),
      variables: SHOW_VARS + v(:buyer_name, :amount, :what, :fees_kept, :reason, :refunded_by, :order_code, :money_note, :order_url) },
    { key: "ticketing_refund_problem", name: "Ticketing: refund problem", channel: "email",
      subject: "A refund didn't go through: {{buyer_name}}",
      body: %(<p>Refunding {{amount}} to {{buyer_name}} for <strong>{{show_title}}</strong> on {{show_date}} didn't go through: {{problem}}</p><p>They haven't been refunded yet. <a href="{{order_url}}">Open the order</a> to try again.</p>#{FOOTER}),
      variables: SHOW_VARS + v(:buyer_name, :amount, :problem, :order_url) },
    { key: "ticketing_dispute", name: "Ticketing: disputed charge", channel: "email",
      subject: "{{headline}}: {{buyer_name}}, {{amount}}",
      body: %(<p>{{explanation}}</p><p>Order {{order_code}} for <strong>{{show_title}}</strong> on {{show_date}}, {{buyer_name}}, {{amount}}.</p><p><a href="{{order_url}}">View the order</a> — the dispute in Stripe is linked from there.</p>#{FOOTER}),
      variables: SHOW_VARS + v(:headline, :explanation, :buyer_name, :amount, :order_code, :order_url) },
    { key: "ticketing_withdrawal", name: "Ticketing: withdrawal", channel: "email",
      subject: "{{headline}}",
      body: %(<p>{{explanation}}</p><p><a href="{{balance_url}}">Your CocoScout balance</a></p>#{FOOTER}),
      variables: v(:headline, :explanation, :balance_url) },
    { key: "ticketing_cancellation_done", name: "Ticketing: show cancellation done", channel: "email",
      subject: "{{show_title}}, {{show_date}}: {{refunded_count}} refunded",
      body: %(<p>Canceling <strong>{{show_title}}</strong> on {{show_date}} is done: {{refunded_count}} refunded, {{refunded_amount}} in all.{{#failed_count}} {{failed_count}} couldn't be refunded; open each order to try again.{{/failed_count}}</p><p><a href="{{orders_url}}">Orders for this show</a></p>#{FOOTER}),
      variables: SHOW_VARS + v(:refunded_count, :refunded_amount, :failed_count, :orders_url) },

    # --- Invitations and producers.
    { key: "ticketing_door_invitation", name: "Ticketing: door access invitation", channel: "email",
      subject: "{{organization_name}} invited you to work the door",
      body: %(<p>Hi {{first_name}},</p><p>{{inviter_name}} at {{organization_name}} invited you to {{access_description}} at their shows, on your phone, with CocoScout.</p><p><a href="{{accept_url}}">Accept the invitation</a></p><p>You'll sign in, or make a free CocoScout account if you don't have one. Then open cocoscout.com/door on show nights.</p>),
      variables: v(:first_name, :inviter_name, :organization_name, :access_description, :accept_url) },
    { key: "ticket_sales_invitation", name: "Ticketing: sales viewer invitation", channel: "email",
      subject: "{{organization_name}} is sharing ticket sales for {{what}} with you",
      body: %(<p>Hi {{first_name}},</p><p>{{inviter_name}} at {{organization_name}} wants you to see how tickets are selling for {{what}}: how many are sold, who's coming, and how the night went.</p><p><a href="{{accept_url}}">See the sales</a></p><p>You'll sign in, or make a free CocoScout account if you don't have one. Then it's under Ticket Sales whenever you want a look.</p>),
      variables: v(:first_name, :inviter_name, :organization_name, :what, :accept_url) },
    { key: "ticket_sales_producer_daily", name: "Ticketing: producer's daily sales", channel: "email",
      subject: "Ticket sales for your shows at {{organization_name}}",
      body: %(<p>Hi {{first_name}},</p><p>Here's where your shows at {{organization_name}} stand this morning.</p>{{rows}}<p style="margin-top:16px"><a href="{{sales_url}}">See the details</a> · You asked for this note; turn it off there any time.</p>),
      variables: v(:first_name, :organization_name, :rows, :sales_url) }
  ].freeze

  # Seeds whichever of these are missing; with overwrite, rewrites the words
  # of the ones named (or all), the way a copy revision ships.
  def self.ensure!(keys: nil, overwrite: false)
    TEMPLATES.each do |spec|
      next if keys && !keys.include?(spec[:key])

      template = ContentTemplate.find_or_initialize_by(key: spec[:key])
      next if template.persisted? && !overwrite

      template.assign_attributes(name: spec[:name], category: "ticketing", channel: spec[:channel], template_type: "structured",
                                 active: true, subject: spec[:subject], body: spec[:body], available_variables: spec[:variables])
      template.save!
    end
  end
end
