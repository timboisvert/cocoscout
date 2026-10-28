class My::MessagesController < ApplicationController
  include MessagesInbox
  include OrganizationContext
  include ContactableProductions
  before_action :require_authentication
  before_action :set_sidebar
  before_action :track_inbox_visit, only: [ :index, :show, :production ]
  rescue_from ActiveRecord::RecordNotFound, with: :message_not_found

  # The one Messages page lives at /messages now (MessagesController).
  def index
    redirect_to messages_path(request.query_parameters), status: :moved_permanently
  end

  # A tap on an inbox row, a push, or Reply on a notification: a thread of a
  # production this person runs opens in production mode for its organization
  # (switching organization when it's another one); a thread they're in as a
  # performer opens in the frame they're already in, production mode's or
  # My's, and switches nothing (Tim, 2026-10-21).
  def open
    thread = Message.root_messages.find(params[:id]) # rubocop:disable CocoScout/UnscopedFind -- gated by the inbox check below
    user = Current.user
    unless thread.subscribed?(user) || Message.manage_inbox_for(user, user.accessible_organizations).exists?(id: thread.id)
      redirect_to messages_path, alert: "You don't have access to this message" and return
    end

    production_ids = user.production_ids_everywhere
    organization_ids = user.accessible_organizations.pluck(:id)
    production_side = production_ids.include?(thread.production_id) ||
                      (thread.production_id.nil? && organization_ids.include?(thread.organization_id))
    organization_id = thread.organization_id || thread.production&.organization_id
    if production_side && organization_id && organization_ids.include?(organization_id)
      switch_organization!(organization_id)
      redirect_to manage_message_path(thread)
    elsif in_production_mode? && (set_current_organization || Current.organization)
      redirect_to manage_message_path(thread) # read it right here, in production mode's frame
    else
      redirect_to my_message_path(thread)
    end
  end

  # GET /my/messages/production/:production_id
  def production
    @show_my_sidebar = true
    @production = Production.find(params[:production_id])

    # Get messages for this production that user is subscribed to
    # Note: system-generated messages ARE shown here (talent needs to see their notifications)
    @messages = Current.user.subscribed_message_threads
                           .where(production: @production)
                           .includes(:sender, :message_recipients, :child_messages, :show, :message_poll, images_attachments: :blob)
                           .order(updated_at: :desc)

    @pagy, @messages = pagy(@messages, limit: 25)
    @thread_summaries = Message.thread_summaries_for(@messages, current_user: Current.user)
    @hide_production_via = true  # Don't show "via" since we're already filtered by production
  end

  def show
    @show_my_sidebar = true
    @message = Message.find(params[:id])
    @root_message = @message.root_message

    # Clear focus param if trying to comment on a deleted message
    if @root_message.deleted? && params[:focus] == "comment"
      redirect_to my_message_path(@root_message) and return
    end

    # Ensure user has access (subscribed to thread)
    unless @root_message.subscribed?(Current.user)
      redirect_to messages_path, alert: "You don't have access to this message"
      return
    end

    # Mark thread as read for this user
    subscription = @root_message.message_subscriptions.find_by(user: Current.user)
    subscription&.mark_read!

    # Also mark as read for the user's person if they're a recipient
    # A user can have multiple Person records (one per org), so find the one
    # that's actually a recipient on this message
    if Current.user.people.any?
      recipient_person = @root_message.message_recipients
                          .where(recipient_type: "Person", recipient_id: Current.user.people.select(:id))
                          .first&.recipient
      recipient_person&.then { |p| @root_message.mark_read_for!(p) }
    end

    # Load all messages in thread (root + descendants), with everything the
    # thread view reads per message so rendering is query-free
    @thread_messages = Message.where(id: [ @root_message.id ] + @root_message.descendant_ids)
                              .includes(:sender, :rich_text_body,
                                        { images_attachments: :blob },
                                        { message_recipients: :recipient },
                                        { message_reactions: { user: { default_person: { profile_headshots: { image_attachment: :blob } } } } },
                                        message_poll: :message_poll_options)
                              .order(:created_at)
    Message.preload_recipient_headshots(@thread_messages)
  end

  def archive
    @message = Message.find(params[:id])
    @root_message = @message.root_message

    # Archive at the subscription level — that's what the inbox is built from.
    Current.user.message_subscriptions.find_by(message: @root_message)&.archive!
    # Keep the recipient-level flag in sync for any per-recipient views.
    @root_message.archive_for!(Current.user.person) if Current.user.person

    respond_to do |format|
      format.html { redirect_back_or_to my_messages_path, notice: "Message archived" }
      format.turbo_stream
    end
  end

  def unarchive
    @message = Message.find(params[:id])
    @root_message = @message.root_message

    Current.user.message_subscriptions.find_by(message: @root_message)&.unarchive!
    if Current.user.person
      @root_message.message_recipients.find_by(recipient: Current.user.person)&.unarchive!
    end

    respond_to do |format|
      format.html { redirect_back_or_to my_messages_path(filter: "archived"), notice: "Message unarchived" }
      format.turbo_stream
    end
  end

  def mark_all_read
    Current.user.message_subscriptions.active.each(&:mark_read!)
    redirect_to messages_path, notice: "All messages marked as read"
  end

  # Flip a thread back to "unread" — bumps the subscription's unread counter
  # and clears the user's recipient read_at so it reappears as unread.
  def mark_unread
    message = Message.find(params[:id])
    root = message.root_message

    subscription = root.message_subscriptions.find_by(user: Current.user)
    subscription&.mark_unread!

    if Current.user.people.any?
      recipient_person = root.message_recipients
                             .where(recipient_type: "Person", recipient_id: Current.user.people.select(:id))
                             .first&.recipient
      recipient_person&.then { |p| root.mark_unread_for!(p) }
    end

    redirect_to my_messages_path, notice: "Marked as unread"
  end

  def mute
    @message = Message.find(params[:id])
    @root_message = @message.root_message

    subscription = @root_message.message_subscriptions.find_by(user: Current.user)
    subscription&.mute!

    redirect_to my_messages_path, notice: "Thread muted"
  end

  def unmute
    @message = Message.find(params[:id])
    @root_message = @message.root_message

    subscription = @root_message.message_subscriptions.find_by(user: Current.user)
    subscription&.unmute!

    redirect_to my_messages_path, notice: "Thread unmuted"
  end

  # POST /my/messages/:id/reply
  def reply
    # Find the parent message - user needs to be subscribed to the ROOT message
    parent_message_id = params[:parent_message_id] || params[:id]
    parent = Message.find(parent_message_id)
    images = params[:images]&.reject(&:blank?)

    # Find root message
    root_message = parent.root_message

    # Prevent replying to deleted messages
    if parent.deleted?
      redirect_to my_message_path(root_message), alert: "Cannot reply to a deleted message"
      return
    end

    # Ensure user is subscribed to the thread
    unless root_message.subscribed?(Current.user)
      redirect_to my_messages_path, alert: "You don't have access to this thread"
      return
    end

    # Check if message is repliable
    unless root_message.repliable?
      redirect_to my_message_path(root_message), alert: "Cannot reply to this message"
      return
    end

    # For system-generated (or senderless) messages with a production, reply goes to
    # the production team. This creates a NEW conversation thread (not nested under
    # the system message) so it shows up properly in /manage/messages for the team.
    # Mirrors Manage::MessagesController — a message with no sender has no one else
    # to reply to.
    if (root_message.system_generated? || root_message.sender.nil?) && root_message.effective_production.present?
      message = MessageService.send_to_production_team(
        production: root_message.effective_production,
        sender: Current.user,
        subject: "Re: #{root_message.subject}",
        body: params[:body]
        # Note: no parent_message - this creates a new root thread
      )
      # Link to the original message for context
      message&.add_regards(root_message) if message
      redirect_target = message # New thread, redirect to it
    else
      # Replies from /my/messages are always personal (not "as production team")
      # Only producers using /manage/messages can choose to reply as production team
      message = MessageService.reply(
        sender: Current.user,
        parent_message: parent,
        body: params[:body],
        visibility: "personal"
      )
      redirect_target = root_message # Same thread, redirect to root
    end
    message&.images&.attach(images) if images.present?

    respond_to do |format|
      format.html { redirect_to my_message_path(redirect_target || root_message), notice: "Reply sent" }
    end
  end

  # POST /my/messages/:id/react/:emoji
  def react
    message = Message.find(params[:id])
    emoji = params[:emoji]

    # Only thread participants may react (as on the manage side): this also
    # renders the message's reactions, with who made them.
    unless message.root_message.subscribed?(Current.user)
      head :forbidden
      return
    end

    # Validate emoji is in allowed list
    unless MessageReaction::REACTIONS.include?(emoji)
      head :unprocessable_content
      return
    end

    added = message.toggle_reaction!(Current.user, emoji)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "reactions_#{message.id}",
          partial: "shared/messages/reactions",
          locals: { message: message }
        )
      end
      format.html { redirect_back fallback_location: my_message_path(message.root_message) }
    end
  end

  # DELETE /my/messages/:id
  def destroy
    message = Message.find_by(id: params[:id])

    if message.nil?
      redirect_to messages_path, alert: "Message not found"
      return
    end

    unless message.can_be_deleted_by?(Current.user)
      redirect_back fallback_location: my_messages_path, alert: "You can only delete your own messages"
      return
    end

    root = message.root_message
    is_root = message.parent_message_id.nil?

    message.smart_delete!

    if is_root
      redirect_to my_messages_path, notice: "Message deleted"
    else
      redirect_to my_message_path(root), notice: "Reply deleted"
    end
  end

  # POST /my/messages/:id/vote_poll
  def vote_poll
    message = Message.find(params[:id])
    root_message = message.root_message

    unless root_message.subscribed?(Current.user)
      redirect_to messages_path, alert: "You don't have access to this message"
      return
    end

    poll = message.message_poll
    unless poll
      redirect_back fallback_location: my_messages_path, alert: "No poll found"
      return
    end

    option = poll.message_poll_options.find_by(id: params[:option_id])
    unless option
      redirect_back fallback_location: my_message_path(root_message), alert: "Invalid poll option"
      return
    end

    unless poll.accepting_votes?
      redirect_back fallback_location: my_message_path(root_message), alert: "This poll is closed"
      return
    end

    existing_vote = option.message_poll_votes.find_by(user: Current.user)
    if existing_vote
      # Toggle off - remove vote
      existing_vote.destroy!
    else
      # For single-vote polls (max_votes = 1), remove any existing vote first
      if poll.max_votes == 1
        poll.message_poll_votes.where(user: Current.user).destroy_all
      end

      # Add vote (max_votes validated in model for multi-vote polls)
      vote = option.message_poll_votes.new(user: Current.user)
      unless vote.save
        redirect_back fallback_location: my_message_path(root_message), alert: vote.errors.full_messages.first
        return
      end
    end

    redirect_back fallback_location: my_message_path(root_message)
  end

  # POST /my/messages/:id/close_poll
  def close_poll
    message = Message.find(params[:id])
    poll = message.message_poll

    unless poll && poll.created_by?(Current.user)
      redirect_back fallback_location: my_messages_path, alert: "Only the poll creator can close it"
      return
    end

    poll.close!
    redirect_back fallback_location: my_message_path(message.root_message), notice: "Poll closed"
  end

  private

  def set_sidebar
    @show_my_sidebar = true
  end

  def track_inbox_visit
    Current.user.touch(:last_inbox_visit_at)
  end

  def message_not_found
    redirect_to messages_path, alert: "Message not found"
  end
end
