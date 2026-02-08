class My::MessagesController < ApplicationController
  before_action :require_authentication
  before_action :set_sidebar
  before_action :track_inbox_visit, only: [ :index, :show, :production ]
  rescue_from ActiveRecord::RecordNotFound, with: :message_not_found

  def index
    @show_my_sidebar = true

    # Filter params
    @filter = params[:filter] || "all"
    @search = params[:q].to_s.strip
    @production_filter = params[:production_id]
    @order = params[:order] || "newest"

    # Base query - show root messages for threads user is subscribed to
    @messages = Current.user.subscribed_message_threads
                           .includes(:sender, :message_recipients, :child_messages, :production, :show, :message_poll, images_attachments: :blob)

    # Apply filters
    case @filter
    when "unread"
      unread_thread_ids = Current.user.message_subscriptions.unread.pluck(:message_id)
      @messages = @messages.where(id: unread_thread_ids)
    end

    # Filter by production
    if @production_filter.present?
      @messages = @messages.where(production_id: @production_filter)
    end

    # Search filter (body is in action_text_rich_texts table)
    if @search.present?
      @messages = @messages
        .left_joins(:rich_text_body)
        .where("messages.subject ILIKE :q OR action_text_rich_texts.body ILIKE :q", q: "%#{@search}%")
    end

    # Apply ordering
    @messages = @order == "oldest" ? @messages.order(updated_at: :asc) : @messages.order(updated_at: :desc)
    @pagy, @messages = pagy(@messages, items: 25)
    @unread_count = Current.user.unread_message_count

    # For production dropdown
    @user_productions = Current.user.subscribed_message_threads.where.not(production_id: nil).distinct.pluck(:production_id)
    @user_productions = Production.where(id: @user_productions).order(:name)

    # For "Contact Production Team" card - get productions user is in talent pool for
    @contactable_productions = productions_user_can_contact
  end

  # GET /my/messages/production/:production_id
  def production
    @show_my_sidebar = true
    @production = Production.find(params[:production_id])

    # Get messages for this production that user is subscribed to
    @messages = Current.user.subscribed_message_threads
                           .where(production: @production)
                           .includes(:sender, :message_recipients, :child_messages, :show, :message_poll, images_attachments: :blob)
                           .order(updated_at: :desc)

    @pagy, @messages = pagy(@messages, items: 25)
    @hide_production_via = true  # Don't show "via" since we're already filtered by production
  end

  def show
    @show_my_sidebar = true
    @message = Message.find(params[:id])
    @root_message = @message.root_message

    # Ensure user has access (subscribed to thread)
    unless @root_message.subscribed?(Current.user)
      redirect_to my_messages_path, alert: "You don't have access to this message"
      return
    end

    # Mark thread as read for this user
    subscription = @root_message.message_subscriptions.find_by(user: Current.user)
    subscription&.mark_read!

    # Also mark as read for the user's person if they're a recipient
    if Current.user.person
      @root_message.mark_read_for!(Current.user.person)
    end

    # Load all messages in thread (root + descendants)
    @thread_messages = Message.where(id: [ @root_message.id ] + @root_message.descendant_ids)
                              .includes(:sender, :message_recipients, message_poll: :message_poll_options)
                              .order(:created_at)
  end

  def archive
    @message = Message.find(params[:id])
    @root_message = @message.root_message

    # Archive for this user's person
    if Current.user.person
      @root_message.archive_for!(Current.user.person)
    end

    respond_to do |format|
      format.html { redirect_to my_messages_path, notice: "Message archived" }
      format.turbo_stream
    end
  end

  def mark_all_read
    Current.user.message_subscriptions.active.each(&:mark_read!)
    redirect_to my_messages_path, notice: "All messages marked as read"
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

    # Ensure user is subscribed to the thread
    unless root_message.subscribed?(Current.user)
      redirect_to my_messages_path, alert: "You don't have access to this thread"
      return
    end

    message = MessageService.reply(
      sender: Current.user,
      parent_message: parent,
      body: params[:body]
    )
    message&.images&.attach(images) if images.present?

    respond_to do |format|
      format.html { redirect_to my_message_path(root_message), notice: "Reply sent" }
    end
  end

  # POST /my/messages/:id/react/:emoji
  def react
    message = Message.find(params[:id])
    emoji = params[:emoji]

    # Validate emoji is in allowed list
    unless MessageReaction::REACTIONS.include?(emoji)
      head :unprocessable_entity
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
      redirect_to my_messages_path, alert: "Message not found"
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
      redirect_to my_messages_path, alert: "You don't have access to this message"
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
      # Add vote (max_votes validated in model)
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
    redirect_to my_messages_path, alert: "Message not found"
  end

  # Get productions where user is in the talent pool (can contact the team)
  def productions_user_can_contact
    return [] unless Current.user.person

    people_ids = Current.user.people.active.pluck(:id)
    return [] if people_ids.empty?

    # Get groups user is a member of
    group_ids = GroupMembership.where(person_id: people_ids).pluck(:group_id)

    production_ids = Set.new

    # Productions via person's direct talent pool memberships
    person_production_ids = TalentPoolMembership
      .where(member_type: "Person", member_id: people_ids)
      .joins(:talent_pool)
      .pluck("talent_pools.production_id")
    production_ids.merge(person_production_ids)

    # Productions via shared talent pools
    if people_ids.any?
      shared_person_production_ids = Production
        .joins(talent_pool_shares: { talent_pool: :talent_pool_memberships })
        .where(talent_pool_memberships: { member_type: "Person", member_id: people_ids })
        .pluck(:id)
      production_ids.merge(shared_person_production_ids)
    end

    # Productions via group's talent pool memberships
    if group_ids.any?
      group_production_ids = TalentPoolMembership
        .where(member_type: "Group", member_id: group_ids)
        .joins(:talent_pool)
        .pluck("talent_pools.production_id")
      production_ids.merge(group_production_ids)

      shared_group_production_ids = Production
        .joins(talent_pool_shares: { talent_pool: :talent_pool_memberships })
        .where(talent_pool_memberships: { member_type: "Group", member_id: group_ids })
        .pluck(:id)
      production_ids.merge(shared_group_production_ids)
    end

    # Productions where user is cast in shows (person or group assignments)
    if people_ids.any?
      cast_production_ids = Production
        .joins(shows: :show_person_role_assignments)
        .where(show_person_role_assignments: { assignable_type: "Person", assignable_id: people_ids })
        .distinct
        .pluck(:id)
      production_ids.merge(cast_production_ids)
    end

    if group_ids.any?
      group_cast_production_ids = Production
        .joins(shows: :show_person_role_assignments)
        .where(show_person_role_assignments: { assignable_type: "Group", assignable_id: group_ids })
        .distinct
        .pluck(:id)
      production_ids.merge(group_cast_production_ids)
    end

    Production.where(id: production_ids).order(:name)
  end
end
