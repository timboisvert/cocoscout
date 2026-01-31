class MessageDigestMailer < ApplicationMailer
  def unread_digest(user:, messages:)
    @user = user
    @messages = messages
    @message_count = messages.size
    @inbox_url = my_inbox_index_url

    mail(
      to: @user.email_address,
      subject: "You have #{@message_count} unread #{'message'.pluralize(@message_count)} on CocoScout"
    )
  end

  private

  def build_messages_summary(messages)
    # Build HTML list of messages (just sender + subject, no body content)
    messages.first(5).map do |msg|
      "<li><strong>#{msg.sender_name}</strong>: #{msg.subject}</li>"
    end.join("\n")
  end
end
