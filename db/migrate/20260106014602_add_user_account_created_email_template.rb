# frozen_string_literal: true

class AddUserAccountCreatedEmailTemplate < ActiveRecord::Migration[8.1]
  def up
    return unless defined?(EmailTemplate)

    EmailTemplate.find_or_create_by!(key: "user_account_created") do |template|
      template.name = "User Account Created"
      template.category = "system"
      template.subject = "New User Signup: {{user_email}}"
      template.description = "Sent to superadmins when a new user account is created."
      template.template_type = "structured"
      template.mailer_class = "AdminMailer"
      template.mailer_action = "user_account_created"
      template.body = <<~HTML
        <p>A new user account has been created on CocoScout.</p>

        <p><strong>Account Details:</strong></p>
        <ul>
          <li><strong>Email:</strong> {{user_email}}</li>
          <li><strong>User ID:</strong> {{user_id}}</li>
          <li><strong>Created at:</strong> {{created_at}}</li>
          <li><strong>Person Name:</strong> {{person_name}}</li>
        </ul>

        <p><a href="{{admin_url}}">View in Admin Panel</a></p>
      HTML
      template.available_variables = [
        { "name" => "user_email", "description" => "The new user's email address" },
        { "name" => "user_id", "description" => "The user's ID" },
        { "name" => "created_at", "description" => "When the account was created" },
        { "name" => "person_name", "description" => "The person's name" },
        { "name" => "admin_url", "description" => "URL to view user in admin panel" }
      ]
      template.active = true
    end
  end

  def down
    return unless defined?(EmailTemplate)

    EmailTemplate.find_by(key: "user_account_created")&.destroy
  end
end
