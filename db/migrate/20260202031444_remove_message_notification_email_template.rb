class RemoveMessageNotificationEmailTemplate < ActiveRecord::Migration[8.1]
  def up
    execute "DELETE FROM email_templates WHERE key = 'message_notification'"
  end

  def down
    # Recreate the old template if rolling back
    execute <<-SQL
      INSERT INTO email_templates (key, name, category, subject, description, template_type, mailer_class, mailer_action, active, body, available_variables, created_at, updated_at)
      VALUES (
        'message_notification',
        'New Message Notification',
        'notification',
        'New message from {{sender_name}}: {{subject}}',
        'Sent immediately when someone receives a new message.',
        'structured',
        'MessageNotificationMailer',
        'new_message',
        true,
        '<p>Hi {{recipient_name}},</p>
<p>You have a new message from {{sender_name}}:</p>
<p><strong>{{subject}}</strong></p>
<p><a href="{{message_url}}">View Message</a></p>',
        '[{"name":"recipient_name","description":"Name of the recipient"},{"name":"sender_name","description":"Name of the sender"},{"name":"subject","description":"Message subject"},{"name":"message_url","description":"URL to view the message"}]',
        NOW(),
        NOW()
      )
      ON CONFLICT (key) DO NOTHING
    SQL
  end
end
