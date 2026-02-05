class RemoveOldMessagingEmailTemplates < ActiveRecord::Migration[8.1]
  def up
    # Remove old email templates that were replaced by in-app messaging
    execute "DELETE FROM email_templates WHERE name IN ('Production Message', 'Talent Pool Message')"

    # Create new message notification template
    execute <<-SQL
      INSERT INTO email_templates (key, name, category, template_type, subject, body, created_at, updated_at)
      VALUES (
        'message_notification',
        'Message Notification',
        'notification',
        'hybrid',
        'New message from {{sender_name}}',
        '<p>You have a new message from <strong>{{sender_name}}</strong> on CocoScout.</p>

<p><strong>Subject:</strong> {{subject}}</p>

<p>
  <a href="{{message_url}}" style="display: inline-block; background: #ec4899; color: white; padding: 12px 30px; text-decoration: none; border-radius: 6px; font-weight: bold;">Read Message on CocoScout</a>
</p>

<p style="color: #6b7280; font-size: 14px;">This message is waiting for you in your CocoScout inbox.</p>',
        NOW(),
        NOW()
      )
      ON CONFLICT (key) DO NOTHING
    SQL
  end

  def down
    # Remove the new template
    execute "DELETE FROM email_templates WHERE key = 'message_notification'"

    # These were passthrough templates, recreating them for rollback
    execute <<-SQL
      INSERT INTO email_templates (name, template_type, subject, body, key, created_at, updated_at)
      VALUES (
        'Production Message',
        'passthrough',
        '{{subject}}',
        '{{body}}',
        'production_message',
        NOW(),
        NOW()
      )
      ON CONFLICT (key) DO NOTHING
    SQL

    execute <<-SQL
      INSERT INTO email_templates (name, template_type, subject, body, key, created_at, updated_at)
      VALUES (
        'Talent Pool Message',
        'passthrough',
        '{{subject}}',
        '{{body}}',
        'talent_pool_message',
        NOW(),
        NOW()
      )
      ON CONFLICT (key) DO NOTHING
    SQL
  end
end
