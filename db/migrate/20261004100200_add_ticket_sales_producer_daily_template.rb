# frozen_string_literal: true

# The morning note to a producer who asked for one: how their upcoming
# shows are selling.
class AddTicketSalesProducerDailyTemplate < ActiveRecord::Migration[8.1]
  TEMPLATE = {
    key: "ticket_sales_producer_daily",
    name: "Ticketing: producer's daily sales",
    subject: "Ticket sales for your shows at {{organization_name}}",
    body: <<~HTML,
      <p>Hi {{first_name}},</p>
      <p>Here's where your shows at {{organization_name}} stand this morning.</p>
      {{rows}}
      <p><a href="{{sales_url}}">See the details</a> · You asked for this note; turn it off there any time.</p>
    HTML
    variables: [
      { "name" => "first_name", "description" => "The producer's first name" },
      { "name" => "organization_name", "description" => "The theater" },
      { "name" => "rows", "description" => "A table of their upcoming shows and how each is selling" },
      { "name" => "sales_url", "description" => "Their Ticket Sales page" }
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
