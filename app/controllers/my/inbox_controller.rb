class My::InboxController < ApplicationController
  before_action :require_authentication
  before_action :set_sidebar

  def index
    @show_my_sidebar = true
    @messages = Current.user.received_messages
                            .top_level
                            .active
                            .includes(:sender, :recipient, :regarding, :message_batch)
                            .order(created_at: :desc)
    @pagy, @messages = pagy(@messages, items: 25)
    @unread_count = Current.user.unread_message_count
  end

  def show
    @show_my_sidebar = true
    @message = Current.user.received_messages.find(params[:id])
    @message.mark_as_read!

    # Load replies (threaded)
    @replies = @message.replies.includes(:sender, :recipient).order(:created_at)

    # If part of a batch, show recipient count
    @batch = @message.message_batch
  end

  def archive
    @message = Current.user.received_messages.find(params[:id])
    @message.update!(archived_at: Time.current)

    respond_to do |format|
      format.html { redirect_to my_inbox_index_path, notice: "Message archived" }
      format.turbo_stream
    end
  end

  def mark_read
    @message = Current.user.received_messages.find(params[:id])
    @message.mark_as_read!

    respond_to do |format|
      format.html { redirect_to my_inbox_index_path }
      format.turbo_stream
    end
  end

  def mark_all_read
    Current.user.unread_messages.update_all(read_at: Time.current)
    redirect_to my_inbox_index_path, notice: "All messages marked as read"
  end

  # POST /my/inbox/:id/reply
  def reply
    parent = Current.user.received_messages.find(params[:id])

    @reply = Message.create!(
      sender: Current.user.person,
      recipient: parent.sender.is_a?(Person) ? parent.sender : parent.sender.person,
      parent: parent,
      organization: parent.organization,
      regarding: parent.regarding,
      subject: "Re: #{parent.subject}",
      body: params[:body],
      message_type: :direct
    )

    respond_to do |format|
      format.html { redirect_to my_inbox_path(parent), notice: "Reply sent" }
      format.turbo_stream
    end
  end

  private

  def set_sidebar
    @show_my_sidebar = true
  end
end
