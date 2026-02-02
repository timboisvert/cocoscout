class AddUnreadDigestEmailTemplate < ActiveRecord::Migration[8.1]
  def up
    EmailTemplate.create!(
      key: "unread_digest",
      name: "Unread Messages Digest",
      category: "notification",
      subject: "You have unread messages on CocoScout",
      description: "Sent to users who have unread messages and haven't checked their inbox recently. Contains a list of threads with unread counts.",
      template_type: "structured",
      mailer_class: "MessageNotificationMailer",
      mailer_action: "unread_digest",
      active: true,
      body: <<~HTML,
        <p>Hi {{recipient_name}},</p>
        <p>You have unread messages waiting for you on CocoScout:</p>
        {{thread_list}}
        <p>
          <a href="{{inbox_url}}" style="display: inline-block; background-color: #db2777; color: white; padding: 12px 28px; border-radius: 8px; text-decoration: none; font-weight: 600;">View Your Messages</a>
        </p>
        <p style="color: #9ca3af; font-size: 13px; text-align: center;">We'll only send you these reminders occasionally if you have unread messages.</p>
      HTML
      available_variables: [
        { name: "recipient_name", description: "First name of the recipient" },
        { name: "inbox_url", description: "URL to the user's inbox" },
        { name: "thread_list", description: "HTML list of threads with unread counts" }
      ]
    )
  end

  def down
    EmailTemplate.find_by(key: "unread_digest")&.destroy
  end
end
