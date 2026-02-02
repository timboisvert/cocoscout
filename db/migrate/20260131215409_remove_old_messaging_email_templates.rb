class RemoveOldMessagingEmailTemplates < ActiveRecord::Migration[8.1]
  def up
    # Remove old email templates that were replaced by in-app messaging
    templates_to_remove = [ 'Production Message', 'Talent Pool Message' ]
    EmailTemplate.where(name: templates_to_remove).destroy_all

    # Create new message notification template
    EmailTemplate.create!(
      key: 'message_notification',
      name: 'Message Notification',
      category: 'notification',
      template_type: 'hybrid',
      subject: 'New message from {{sender_name}}',
      body: <<~HTML
        <p>You have a new message from <strong>{{sender_name}}</strong> on CocoScout.</p>

        <p><strong>Subject:</strong> {{subject}}</p>

        <p>
          <a href="{{message_url}}" style="display: inline-block; background: #ec4899; color: white; padding: 12px 30px; text-decoration: none; border-radius: 6px; font-weight: bold;">Read Message on CocoScout</a>
        </p>

        <p style="color: #6b7280; font-size: 14px;">This message is waiting for you in your CocoScout inbox.</p>
      HTML
    )
  end

  def down
    # Remove the new template
    EmailTemplate.find_by(key: 'message_notification')&.destroy

    # These were passthrough templates, recreating them for rollback
    EmailTemplate.create!(
      name: 'Production Message',
      template_type: 'passthrough',
      subject: '{{subject}}',
      body: '{{body}}'
    )

    EmailTemplate.create!(
      name: 'Talent Pool Message',
      template_type: 'passthrough',
      subject: '{{subject}}',
      body: '{{body}}'
    )
  end
end
