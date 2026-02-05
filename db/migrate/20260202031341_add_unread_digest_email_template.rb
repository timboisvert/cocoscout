class AddUnreadDigestEmailTemplate < ActiveRecord::Migration[8.1]
  def up
    execute <<-SQL
      INSERT INTO email_templates (key, name, category, subject, description, template_type, mailer_class, mailer_action, active, body, available_variables, created_at, updated_at)
      VALUES (
        'unread_digest',
        'Unread Messages Digest',
        'notification',
        'You have unread messages on CocoScout',
        'Sent to users who have unread messages and haven''t checked their inbox recently. Contains a list of threads with unread counts.',
        'structured',
        'MessageNotificationMailer',
        'unread_digest',
        true,
        '<p>Hi {{recipient_name}},</p>
<p>You have unread messages waiting for you on CocoScout:</p>
{{thread_list}}
<p>
  <a href="{{inbox_url}}" style="display: inline-block; background-color: #db2777; color: white; padding: 12px 28px; border-radius: 8px; text-decoration: none; font-weight: 600;">View Your Messages</a>
</p>
<p style="color: #9ca3af; font-size: 13px; text-align: center;">We''ll only send you these reminders occasionally if you have unread messages.</p>',
        '[{"name":"recipient_name","description":"First name of the recipient"},{"name":"inbox_url","description":"URL to the user''s inbox"},{"name":"thread_list","description":"HTML list of threads with unread counts"}]',
        NOW(),
        NOW()
      )
      ON CONFLICT (key) DO NOTHING
    SQL
  end

  def down
    execute "DELETE FROM email_templates WHERE key = 'unread_digest'"
  end
end
