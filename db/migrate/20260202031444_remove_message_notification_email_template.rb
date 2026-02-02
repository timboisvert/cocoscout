class RemoveMessageNotificationEmailTemplate < ActiveRecord::Migration[8.1]
  def up
    EmailTemplate.find_by(key: "message_notification")&.destroy
  end

  def down
    # Recreate the old template if rolling back
    EmailTemplate.create!(
      key: "message_notification",
      name: "New Message Notification",
      category: "notification",
      subject: "New message from {{sender_name}}: {{subject}}",
      description: "Sent immediately when someone receives a new message.",
      template_type: "structured",
      mailer_class: "MessageNotificationMailer",
      mailer_action: "new_message",
      active: true,
      body: <<~HTML,
        <p>Hi {{recipient_name}},</p>
        <p>You have a new message from {{sender_name}}:</p>
        <p><strong>{{subject}}</strong></p>
        <p><a href="{{message_url}}">View Message</a></p>
      HTML
      available_variables: [
        { name: "recipient_name", description: "Name of the recipient" },
        { name: "sender_name", description: "Name of the sender" },
        { name: "subject", description: "Message subject" },
        { name: "message_url", description: "URL to view the message" }
      ].to_json
    )
  end
end
