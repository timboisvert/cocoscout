class RemoveUserAccountCreatedContentTemplate < ActiveRecord::Migration[8.1]
  def up
    ContentTemplate.find_by(key: "user_account_created")&.destroy
  end

  def down
    ContentTemplate.find_or_create_by!(key: "user_account_created") do |template|
      template.name = "New User Account Created (Admin Notification)"
      template.description = "Sent to superadmins when a new user account is created"
      template.category = "auth"
      template.subject = "New CocoScout Account: {{user_email}}"
      template.body = "<p>A new user account has been created:</p><p><strong>Email:</strong> {{user_email}}<br><strong>Created:</strong> {{created_at}}</p>"
      template.channel = "email"
      template.mailer_class = "AdminMailer"
      template.mailer_action = "user_account_created"
      template.variables = %w[user_email user_id created_at person_name admin_url]
    end
  end
end
