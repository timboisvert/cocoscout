# frozen_string_literal: true

# Copy for asking staff for their W-9. Like every staffing email, it lives in a
# content template, never inline.
class AddStaffW9ContentTemplates < ActiveRecord::Migration[8.1]
  VARIABLES = [
    { "name" => "first_name", "description" => "Staff member's first name" },
    { "name" => "organization_name", "description" => "Name of the organization" },
    { "name" => "w9_url", "description" => "Link to the staff member's W-9 form" }
  ].freeze

  def up
    ContentTemplate.find_or_create_by!(key: "staff_w9_request") do |t|
      t.name = "Staff W-9 Request"
      t.category = "staffing"
      t.channel = "both"
      t.template_type = "structured"
      t.active = true
      t.subject = "{{organization_name}} needs your tax info (Form W-9)"
      t.body = <<~HTML
        <p>Hi {{first_name}},</p>
        <p><strong>{{organization_name}}</strong> pays you as an independent contractor, so they need a Form W-9 from you to send you a 1099 at tax time.</p>
        <p>It takes about two minutes: your legal name, address, and your Social Security number or EIN.</p>
        <p><a href="{{w9_url}}">Fill out your W-9 →</a></p>
        <p>Your tax ID is encrypted and only shared with {{organization_name}}.</p>
      HTML
      t.available_variables = VARIABLES
    end

    ContentTemplate.find_or_create_by!(key: "staff_w9_reminder") do |t|
      t.name = "Staff W-9 Reminder"
      t.category = "staffing"
      t.channel = "both"
      t.template_type = "structured"
      t.active = true
      t.subject = "Reminder: {{organization_name}} still needs your W-9"
      t.body = <<~HTML
        <p>Hi {{first_name}},</p>
        <p>Just a nudge: <strong>{{organization_name}}</strong> is still waiting on your Form W-9. They need it to send you a 1099 at tax time.</p>
        <p><a href="{{w9_url}}">Fill out your W-9 →</a></p>
      HTML
      t.available_variables = VARIABLES
    end
  end

  def down
    ContentTemplate.where(key: %w[staff_w9_request staff_w9_reminder]).destroy_all
  end
end
