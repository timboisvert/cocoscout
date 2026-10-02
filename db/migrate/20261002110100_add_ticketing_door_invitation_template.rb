# frozen_string_literal: true

# The email inviting someone to work a theater's door (Ticketing settings →
# Door access → invite by email).
class AddTicketingDoorInvitationTemplate < ActiveRecord::Migration[8.1]
  def up
    ContentTemplate.find_or_create_by!(key: "ticketing_door_invitation") do |t|
      t.name = "Ticketing: door access invitation"
      t.category = "ticketing"
      t.channel = "email"
      t.template_type = "structured"
      t.active = true
      t.subject = "{{organization_name}} invited you to work the door"
      t.body = <<~HTML
        <p>Hi {{first_name}},</p>
        <p>{{inviter_name}} at {{organization_name}} invited you to {{access_description}} at their shows, on your phone, with CocoScout.</p>
        <p><a href="{{accept_url}}">Accept the invitation</a></p>
        <p>You'll sign in, or make a free CocoScout account if you don't have one. Then open cocoscout.com/door on show nights.</p>
      HTML
      t.available_variables = [
        { "name" => "first_name", "description" => "The invited person's first name" },
        { "name" => "inviter_name", "description" => "Who sent the invitation" },
        { "name" => "organization_name", "description" => "The theater" },
        { "name" => "access_description", "description" => "e.g. check people in, or work the box office" },
        { "name" => "accept_url", "description" => "Where they accept" }
      ]
    end
  end

  def down
    ContentTemplate.where(key: "ticketing_door_invitation").destroy_all
  end
end
