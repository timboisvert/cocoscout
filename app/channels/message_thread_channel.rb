# Channel for real-time message thread updates
# Handles: new replies, typing indicators, presence
class MessageThreadChannel < ApplicationCable::Channel
  def subscribed
    @message = Message.find(params[:message_id])
    @root = @message.root_message

    # Only allow subscription if user has access to thread (subscribed or is the sender)
    if @root.subscribed?(current_user) || @message.sender == current_user
      stream_for @root  # Always stream for the root message

      # Broadcast presence
      broadcast_presence("joined")
    else
      reject
    end
  end

  def unsubscribed
    broadcast_presence("left") if @root
  end

  # Called when user starts typing
  def typing
    return unless @root

    MessageThreadChannel.broadcast_to(
      @root,
      {
        type: "typing",
        user_id: current_user.id,
        user_name: current_user.person&.name || current_user.email_address,
        timestamp: Time.current.to_i
      }
    )
  end

  # Called when user stops typing
  def stopped_typing
    MessageThreadChannel.broadcast_to(
      @root,
      {
        type: "stopped_typing",
        user_id: current_user.id
      }
    )
  end

  private

  def broadcast_presence(action)
    MessageThreadChannel.broadcast_to(
      @root,
      {
        type: "presence",
        action: action,
        user_id: current_user.id,
        user_name: current_user.person&.name || current_user.email_address
      }
    )
  end
end
