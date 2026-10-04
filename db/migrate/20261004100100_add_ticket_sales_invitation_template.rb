# frozen_string_literal: true

# The email inviting someone to watch a show's ticket sales (the show page →
# Who can see sales → invite by email).
class AddTicketSalesInvitationTemplate < ActiveRecord::Migration[8.1]
  TEMPLATE = {
    key: "ticket_sales_invitation",
    name: "Ticketing: sales viewer invitation",
    subject: "{{organization_name}} is sharing ticket sales for {{what}} with you",
    body: <<~HTML,
      <p>Hi {{first_name}},</p>
      <p>{{inviter_name}} at {{organization_name}} wants you to see how tickets are selling for {{what}}: how many are sold, who's coming, and how the night went.</p>
      <p><a href="{{accept_url}}">See the sales</a></p>
      <p>You'll sign in, or make a free CocoScout account if you don't have one. Then it's under Ticket Sales whenever you want a look.</p>
    HTML
    variables: [
      { "name" => "first_name", "description" => "The invited person's first name" },
      { "name" => "inviter_name", "description" => "Who shared it" },
      { "name" => "organization_name", "description" => "The theater" },
      { "name" => "what", "description" => "The show and date, or the production" },
      { "name" => "accept_url", "description" => "Where they accept" }
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
