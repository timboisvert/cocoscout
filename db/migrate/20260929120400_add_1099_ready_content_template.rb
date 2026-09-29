# frozen_string_literal: true

# Copy for the recipient's "Your 1099 is ready" message.
class Add1099ReadyContentTemplate < ActiveRecord::Migration[8.1]
  def up
    ContentTemplate.find_or_create_by!(key: "staff_1099_ready") do |t|
      t.name = "Staff 1099 Ready"
      t.category = "staffing"
      t.channel = "both"
      t.template_type = "structured"
      t.active = true
      t.subject = "Your {{tax_year}} 1099-NEC from {{organization_name}} is ready"
      t.body = <<~HTML
        <p>Hi {{first_name}},</p>
        <p>Your {{tax_year}} 1099-NEC from <strong>{{organization_name}}</strong> is ready.</p>
        <p>Open it from your account (it's private to you): <a href="{{form_1099_url}}">View your 1099-NEC →</a></p>
        <p>You'll need this when you file your federal taxes.</p>
      HTML
      t.available_variables = [
        { "name" => "first_name", "description" => "Recipient's first name" },
        { "name" => "organization_name", "description" => "Name of the organization" },
        { "name" => "tax_year", "description" => "Tax year the 1099 is for" },
        { "name" => "form_1099_url", "description" => "Link to their 1099 PDF" }
      ]
    end
  end

  def down
    ContentTemplate.find_by(key: "staff_1099_ready")&.destroy
  end
end
