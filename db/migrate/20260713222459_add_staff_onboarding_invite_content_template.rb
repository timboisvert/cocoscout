# frozen_string_literal: true

class AddStaffOnboardingInviteContentTemplate < ActiveRecord::Migration[8.1]
  def up
    ContentTemplate.find_or_create_by!(key: "staff_onboarding_invite") do |t|
      t.name = "Staff Onboarding Invite"
      t.category = "staffing"
      t.channel = "both"
      t.template_type = "structured"
      t.active = true
      t.subject = "Welcome to {{organization_name}} — finish your onboarding"
      t.body = <<~HTML
        <p>Hi {{first_name}},</p>
        <p>You've been added to the team at <strong>{{organization_name}}</strong>! Head to your welcome page to get set up — you'll accept your spot, set up how you get paid, and add your availability. It only takes a minute.</p>
        <p><a href="{{onboarding_url}}">Go to your welcome page →</a></p>
        <p>Your payment details stay secure with our payment processor.</p>
      HTML
      t.available_variables = [
        { "name" => "first_name", "description" => "Staff member's first name" },
        { "name" => "organization_name", "description" => "Name of the organization" },
        { "name" => "onboarding_url", "description" => "Link to the staff member's onboarding welcome page" }
      ]
    end
  end

  def down
    ContentTemplate.find_by(key: "staff_onboarding_invite")&.destroy
  end
end
