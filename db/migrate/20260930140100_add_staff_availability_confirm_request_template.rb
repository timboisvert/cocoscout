# frozen_string_literal: true

# Copy for a manager asking staff to check and confirm their work
# availability. Like every staffing email, it lives in a content template;
# the manager sees and can edit it before it goes (with {{first_name}} filled
# per person).
class AddStaffAvailabilityConfirmRequestTemplate < ActiveRecord::Migration[8.1]
  def up
    ContentTemplate.find_or_create_by!(key: "staff_availability_confirm_request") do |t|
      t.name = "Staff Availability Confirmation Request"
      t.category = "staffing"
      t.channel = "both"
      t.template_type = "hybrid"
      t.active = true
      t.subject = "Is your availability up to date for {{organization_name}}?"
      t.body = <<~HTML
        <p>Hi {{first_name}},</p>
        <p>We're putting the schedule together at <strong>{{organization_name}}</strong>. Could you check when you can work, change anything that's different, and confirm it's up to date?</p>
        <p><a href="{{availability_url}}">Check my availability →</a></p>
        <p>Thanks!</p>
      HTML
      t.available_variables = [
        { "name" => "first_name", "description" => "Staff member's first name" },
        { "name" => "organization_name", "description" => "Name of the organization" },
        { "name" => "availability_url", "description" => "Link to the staff member's Work Availability page" }
      ]
    end
  end

  def down
    ContentTemplate.where(key: "staff_availability_confirm_request").destroy_all
  end
end
