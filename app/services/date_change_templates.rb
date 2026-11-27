# frozen_string_literal: true

# The words of what a date change sends that nothing sent before (Tim,
# 2026-11-27, "Cancel or move this date"). Each is a seeded ContentTemplate.
# The cast and staff notices about a canceled or moved date stay
# ShowChangeNotices' (show_canceled, show_moved, shift_canceled,
# shift_moved); a buyer's refund stays TicketOrderRefund's.
#
# The buyer emails are drafts the manager reads and can edit on the What it
# touches step: one email per buyer, listing all of their tickets. Their
# per-buyer parts ({{dates}}, {{what_happens}}, {{changes}}) are filled in
# for each buyer.
class DateChangeTemplates
  BUYER_VARS = [
    { "name" => "first_name", "description" => "The buyer's first name" },
    { "name" => "organization_name", "description" => "The organization" },
    { "name" => "show_title", "description" => "The show (or shows) the buyer has tickets for" }
  ].freeze
  PERSON_VARS = [
    { "name" => "recipient_name", "description" => "The person's first name" },
    { "name" => "organization_name", "description" => "The organization" },
    { "name" => "production_name", "description" => "The production" }
  ].freeze

  TEMPLATES = [
    { key: "date_change_buyers_canceled", name: "Dates canceled (to ticket buyers)", category: "ticketing", channel: "email",
      subject: "{{show_title}} is canceled",
      body: %(<p>Hi {{first_name}},</p><p>We're sorry: <strong>{{show_title}}</strong> on {{dates}} is canceled.</p><p>{{what_happens}}</p><p>We hope to see you at another show soon.</p><p>{{organization_name}}</p>),
      variables: BUYER_VARS + [
        { "name" => "dates", "description" => "The canceled dates the buyer had tickets for" },
        { "name" => "what_happens", "description" => "What happens to each of their orders: refunded to the card, a pass credit back, and so on" } ] },
    { key: "date_change_buyers_moved", name: "Dates moved (to ticket buyers)", category: "ticketing", channel: "email",
      subject: "{{show_title}} has a new date and time",
      body: %(<p>Hi {{first_name}},</p><p><strong>{{show_title}}</strong> has a new date and time.</p><p>{{changes}}</p><p>Your tickets work as they are, so there's nothing you need to do.</p>{{#refund_link}}<p>If the new time doesn't work for you, you can get a refund any time before the show starts: {{refund_link}}</p>{{/refund_link}}<p>{{organization_name}}</p>),
      variables: BUYER_VARS + [
        { "name" => "changes", "description" => "Each of their dates, was and now" },
        { "name" => "refund_link", "description" => "Where they get a refund, when the manager offers one" } ] },
    { key: "date_change_buyers_rebooked", name: "Tickets moved to another date when a date is canceled (to ticket buyers)", category: "ticketing", channel: "email",
      subject: "{{show_title}}: your tickets are now for {{now}}",
      body: %(<p>Hi {{first_name}},</p><p>We're sorry: <strong>{{show_title}}</strong> on {{was}} is canceled, so {{organization_name}} moved your tickets to {{now}}. The old ones no longer work. Your new tickets: {{order_url}}</p>{{#refund_link}}<p>If that date doesn't work for you, you can get a refund any time before the show starts: {{refund_link}}</p>{{/refund_link}}<p>{{organization_name}}</p>),
      variables: BUYER_VARS + [
        { "name" => "was", "description" => "The canceled date" },
        { "name" => "now", "description" => "The date their tickets are for now" },
        { "name" => "order_url", "description" => "Their tickets" },
        { "name" => "refund_link", "description" => "Where they get a refund" } ] },
    { key: "date_change_buyers_back_on", name: "Canceled dates back on (to ticket buyers who were refunded)", category: "ticketing", channel: "email",
      subject: "{{show_title}} is back on",
      body: %(<p>Hi {{first_name}},</p><p>Good news: <strong>{{show_title}}</strong> is back on for {{dates}}. Your earlier tickets were refunded, so they won't work, but tickets are on sale again.</p><p>Get tickets: {{buy_url}}</p><p>{{organization_name}}</p>),
      variables: BUYER_VARS + [
        { "name" => "dates", "description" => "The dates back on that the buyer had tickets for" },
        { "name" => "buy_url", "description" => "Where to buy" } ] },
    { key: "date_change_cover_not_needed", name: "Cover no longer needed, the date canceled (to people invited to cover)", category: "shows", channel: "message",
      subject: "Cover is no longer needed: {{role_name}}, {{show_label}}",
      body: %(<p>Hi {{recipient_name}}, {{show_label}} is canceled, so cover is no longer needed for {{role_name}}.</p>),
      variables: PERSON_VARS + [
        { "name" => "role_name", "description" => "The role that needed cover" },
        { "name" => "show_label", "description" => "The production and date" } ] },
    { key: "date_change_role_opened", name: "A cast member's role opened for cover after a move (cast)", category: "shows", channel: "both",
      subject: "[{{production_name}}] {{role_name}} is open for cover on {{now}}",
      body: %(<p>Hi {{recipient_name}}, {{production_name}} moved {{was}} to {{now}}. {{reason}}, so {{role_name}} is open for cover that night.</p>),
      variables: PERSON_VARS + [
        { "name" => "role_name", "description" => "Their role" },
        { "name" => "was", "description" => "The date as it was" },
        { "name" => "now", "description" => "The new date and time" },
        { "name" => "reason", "description" => "Why, e.g. You marked Saturday, December 5 as unavailable" } ] },
    { key: "date_change_shift_opened", name: "A shift opened for cover after a move (staff)", category: "shows", channel: "both",
      subject: "{{organization_name}}: No longer scheduled: {{shift}}", push_body: "No longer scheduled: {{shift}}",
      body: %(<p>Hi {{recipient_name}}, {{shift}} moved to {{now}}, which overlaps your {{clash}}. It's open for cover, and you're no longer scheduled for it.</p>),
      variables: PERSON_VARS + [
        { "name" => "shift", "description" => "The shift as it was, e.g. Door, Fri Dec 4, 7:00 PM" },
        { "name" => "now", "description" => "When the shift is now" },
        { "name" => "clash", "description" => "What it overlaps, e.g. Door shift at the Saturday Showcase, 7:00 PM" } ] },
    { key: "show_back_on", name: "Canceled dates back on (cast)", category: "shows", channel: "both",
      subject: "[{{production_name}}] Back on: {{dates}}",
      body: %(<p>Hi {{recipient_name}}, {{production_name}} is back on: {{dates}}. You're cast as {{roles}}.</p>{{#cover}}<p>{{cover}}</p>{{/cover}}),
      variables: PERSON_VARS + [
        { "name" => "dates", "description" => "Their dates back on" },
        { "name" => "roles", "description" => "Their roles" },
        { "name" => "cover", "description" => "A role opened for cover, if theirs was" } ] },
    { key: "shift_back_on", name: "Shifts back on the schedule (staff)", category: "shows", channel: "both",
      subject: "{{organization_name}}: Back on the schedule: {{headline}}", push_body: "Back on the schedule: {{headline}}",
      body: %(<p>Hi {{recipient_name}}, you're back on the schedule: {{shifts}}</p>),
      variables: PERSON_VARS + [
        { "name" => "headline", "description" => "The first shift, e.g. Booth, Fri Dec 4, 7:00 PM" },
        { "name" => "shifts", "description" => "Each of their shifts back on" } ] },
    { key: "date_change_contract_moved", name: "A contract date moved (to the people on the contract)", category: "contracts", channel: "message",
      subject: "{{organization_name}} moved {{production_name}}: {{was}} is now {{now}}",
      body: %(<p>{{organization_name}} moved the date on your contract for {{production_name}}: {{was}} is now {{now}}.</p><p><a href="{{contracts_url}}">Open My Contracts</a></p>),
      variables: PERSON_VARS + [
        { "name" => "was", "description" => "The date and time as it was" },
        { "name" => "now", "description" => "The new date and time" },
        { "name" => "contracts_url", "description" => "My Contracts" } ] }
  ].freeze

  KEYS = TEMPLATES.map { |t| t[:key] }.freeze

  def self.ensure!(keys: nil, overwrite: false)
    TEMPLATES.each do |spec|
      next if keys && !keys.include?(spec[:key])

      template = ContentTemplate.find_or_initialize_by(key: spec[:key])
      next if template.persisted? && !overwrite

      template.assign_attributes(name: spec[:name], category: spec[:category], channel: spec[:channel], template_type: "structured",
                                 active: true, subject: spec[:subject], body: spec[:body], available_variables: spec[:variables])
      template.push_body = spec[:push_body] if spec[:push_body] && template.has_attribute?(:push_body)
      template.save!
    end
  end
end
